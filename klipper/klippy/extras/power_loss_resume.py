# Resuming printing after a power outage
#
# Copyright (C) 2024  Xiaok <xiaok@zxkxz.cn>
#
# This file may be distributed under the terms of the GNU GPLv3 license.
import json
import os, logging, io

INFO_FILE = ".power_loss_recover.json"


def _sanitize_for_json(obj):
    """将 Klipper get_status 等返回的结构递归转为可 json.dump 的类型。"""
    if obj is None:
        return None
    if isinstance(obj, (bool, int, float, str)):
        return obj
    if isinstance(obj, bytes):
        return obj.decode("utf-8", errors="replace")
    if isinstance(obj, dict):
        return {str(k): _sanitize_for_json(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [_sanitize_for_json(x) for x in obj]
    try:
        if hasattr(obj, "__iter__") and not isinstance(obj, (str, bytes)):
            return [_sanitize_for_json(x) for x in obj]
    except Exception:
        pass
    try:
        return float(obj)
    except (TypeError, ValueError):
        pass
    return str(obj)


def _persist_power_loss_json(path, data_dict):
    """
    尽量及时落盘：先写同目录 .tmp，fsync 后再原子 replace 到目标文件，
    并对所在目录 fsync，降低掉电时出现半截 JSON 或旧文件损坏的概率。
    """
    tmp_path = path + ".tmp"
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(data_dict, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, path)
    except Exception:
        try:
            if os.path.isfile(tmp_path):
                os.unlink(tmp_path)
        except OSError:
            pass
        raise
    try:
        dirpath = os.path.dirname(os.path.abspath(path))
        if dirpath:
            dfd = os.open(dirpath, os.O_RDONLY)
            try:
                os.fsync(dfd)
            finally:
                os.close(dfd)
    except OSError:
        pass


class PowerLossResume:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        self.printer.register_event_handler(
            "klippy:analyze_shutdown", self._handle_analyze_shutdown
        )
        self.printer.register_event_handler("klippy:ready", self._handle_ready)

        # power_pin 可选：通用 Klipper 无专用电源键引脚时可不写本项（不加载 [buttons] 注册）
        power_pin = config.get("power_pin", None)
        if power_pin is not None and str(power_pin).strip() != "":
            self.buttons = self.printer.load_object(config, "buttons")
            self.buttons.register_buttons([power_pin], self._power_button_handler)

        self.is_shutdown = config.getboolean("is_shutdown", True)
        self.paused_recover_z = config.getfloat("paused_recover_z", 0.0)
        self.layer_count = config.getint("layer_count", 0)
        # Z 变化触发快照时的最小间隔（秒）；网床/探测时 Z 频繁变化可减轻磁盘与主机负载。
        # 设为 0 则关闭节流（与旧版行为一致，不推荐在慢主机上使用）。
        self.z_snapshot_min_interval = config.getfloat(
            "z_snapshot_min_interval", 1.5, minval=0.0
        )
        gcode_macro = self.printer.load_object(config, "gcode_macro")
        self.shutdown_gcode = gcode_macro.load_template(config, "shutdown_gcode", "")
        self.layer_change_gcode = gcode_macro.load_template(
            config, "layer_change_gcode", ""
        )
        self.start_gcode = gcode_macro.load_template(config, "start_gcode")

        self.gcode_move = self.printer.load_object(config, "gcode_move")
        self.gcode = self.printer.lookup_object("gcode")

        # 虚拟SD卡对象
        self.virtual_sdcard = self.printer.lookup_object("virtual_sdcard", None)
        self.exclude_objects = self.printer.lookup_object("exclude_object", None)
        self.webhooks = self.printer.lookup_object("webhooks")

        # Print Stat Tracking
        self.print_stats = self.printer.load_object(config, "print_stats")

        self.power_loss_info = None
        self.sdcard_dirname = f"/usr/share/{INFO_FILE}"

        self.pheaters = None
        # 用户点「清除续打」后，在本次打印结束或回到空闲前，不再用 Z 快照覆盖 JSON
        self._plr_cleared_by_user = False

        self.gcode.register_command(
            "START_POWER_LOSS_RESUME",
            self.cmd_START_POWER_LOSS_RESUME,
            desc=self.cmd_START_POWER_LOSS_RESUME_help,
        )
        self.gcode.register_command(
            "CLEAR_POWER_LOSS_RESUME",
            self.cmd_CLEAR_POWER_LOSS_RESUME,
            desc=self.cmd_CLEAR_POWER_LOSS_RESUME_help,
        )
        self.webhooks.register_endpoint(
            "power_loss_resume/start_print",
            self._handle_start_power_loss_resume,
        )
        self.webhooks.register_endpoint(
            "power_loss_resume/clear_info",
            self._handle_clear_power_loss_resume_info,
        )
        self.webhooks.register_endpoint(
            "power_loss_resume/get_info",
            self._handle_get_power_loss_resume_info,
        )

    def _handle_analyze_shutdown(self, msg, details):
        logging.info("handle_shutdown")
        self._save_power_loss_info()

    def _handle_ready(self):
        logging.info("handle_ready")
        self.virtual_sdcard = self.printer.lookup_object("virtual_sdcard", None)
        self.exclude_objects = self.printer.lookup_object("exclude_object", None)
        if self.virtual_sdcard is None:
            raise self.printer.config_error(
                "virtual_sdcard not found. Cannot start power loss resume."
            )
        if hasattr(self.virtual_sdcard, "sdcard_dirname"):
            try:
                self.sdcard_dirname = os.path.join(
                    os.path.dirname(self.virtual_sdcard.sdcard_dirname), INFO_FILE
                )
            except ValueError as e:
                raise self.printer.config_error(
                    f"virtual_sdcard.sdcard_dirname not found. Cannot start power loss resume."
                )
        if self.sdcard_dirname is None:
            raise self.printer.config_error(
                "sdcard_dirname not found. Cannot start power loss resume."
            )
        self.pheaters = self.printer.lookup_object("heaters", None)
        if self.pheaters is None:
            raise self.printer.config_error(
                "heaters not found. Cannot start power loss resume."
            )
        self._read_power_loss_info()
        self._validate_resume_snapshot_on_startup()

    def _has_valid_resume_record(self):
        """磁盘/内存中是否有结构完整的可续打记录（不区分是否应对 UI 展示）。"""
        if self.power_loss_info is None:
            return False
        if not self.power_loss_info.get("power_loss_resume"):
            return False
        fp = self.power_loss_info.get("file_path")
        if not fp or fp == "":
            return False
        ps = self.power_loss_info.get("print_stats") or {}
        fn = ps.get("filename")
        if not fn or fn == "":
            return False
        return True

    def _should_expose_resume_to_ui(self, eventtime):
        """
        前端「是否续打」仅在**空闲**时展示：打印中不暴露，避免与当前任务混淆。
        断电恢复场景：重启后未在开始打印前，应展示；Klipper 启动时另做文件校验。
        """
        if not self._has_valid_resume_record():
            return False
        if self._plr_cleared_by_user:
            return False
        if self._printer_is_printing():
            return False
        return True

    def _validate_resume_snapshot_on_startup(self):
        """仅在 klippy:ready 后执行：无效快照清除，避免重启后误提示。"""
        if not self._has_valid_resume_record():
            return
        fp = self.power_loss_info.get("file_path")
        if not fp or not os.path.isfile(fp):
            logging.info(
                "power_loss_resume: 启动校验未通过（G 文件不存在），清除快照"
            )
            self._save_power_loss_info(False)

    def get_status(self, eventtime):
        return {
            "power_loss_resume": self._should_expose_resume_to_ui(eventtime),
        }

    cmd_CLEAR_POWER_LOSS_RESUME_help = "Clear power loss resume info"

    def cmd_CLEAR_POWER_LOSS_RESUME(self, gcmd):
        self._plr_cleared_by_user = True
        self._save_power_loss_info(False)
        gcmd.respond_raw("Power loss resume info cleared")

    cmd_START_POWER_LOSS_RESUME_help = "Start power loss resume print"

    def cmd_START_POWER_LOSS_RESUME(self, gcmd):
        if self.virtual_sdcard.work_timer is not None:
            gcmd.respond_raw("Printing in progress. Unable to operate.")
            return
        if self.power_loss_info is None:
            gcmd.respond_raw("No power loss info found.")
            return
        self.reactor.register_async_callback(
            (lambda e: self._handle_power_loss_resume())
        )
        gcmd.respond_raw("Start power loss resume")

    def _handle_start_power_loss_resume(self, web_request):
        if self.virtual_sdcard.work_timer is not None:
            web_request.send({"msg": "Printing in progress. Unable to operate."})
            return
        if self.power_loss_info is None:
            web_request.send({"msg": "No power loss info found."})
            return
        self.reactor.register_async_callback(
            (lambda e: self._handle_power_loss_resume())
        )
        web_request.send({"msg": "Start power loss resume"})

    def _handle_clear_power_loss_resume_info(self, web_request):
        self._plr_cleared_by_user = True
        self._save_power_loss_info(False)
        web_request.send({"msg": "Clear power loss resume info"})

    def _handle_get_power_loss_resume_info(self, web_request):
        eventtime = self.reactor.monotonic()
        if self._should_expose_resume_to_ui(eventtime):
            ret = {
                "power_loss_resume": True,
                "file_path": self.power_loss_info["file_path"],
                "progress": self.power_loss_info["progress"],
                "filename": self.power_loss_info["print_stats"]["filename"],
            }
        else:
            ret = {
                "power_loss_resume": False,
                "file_path": None,
                "progress": 0,
                "filename": None,
            }
        web_request.send({"power_loss_info": ret})

    def _read_power_loss_info(self):
        if os.path.exists(self.sdcard_dirname):
            with open(self.sdcard_dirname, "r", encoding="utf-8") as file:
                try:
                    text = file.read()
                    text = text.encode("utf-8").decode("unicode_escape")
                    self.power_loss_info = json.loads(text)
                except:
                    logging.exception("Json load error")
                    self.power_loss_info = None
        else:
            self.power_loss_info = None

    def _printer_is_printing(self):
        """判断是否在打印/暂停；不依赖 Printer._is_printing（上游 Klipper 可能无此方法）。"""
        eventtime = self.reactor.monotonic()
        # SD 卡打印进行中时最可靠：print_stats 偶发未切到 printing 时仍应有 work_timer
        vs = self.virtual_sdcard
        if vs is not None and vs.work_timer is not None:
            return True
        try:
            ps = self.print_stats.get_status(eventtime)
            if ps.get("state") in ("printing", "paused"):
                return True
        except Exception:
            pass
        idle_timeout = self.printer.lookup_object("idle_timeout", None)
        if idle_timeout is not None:
            try:
                if idle_timeout.get_status(eventtime)["state"] == "Printing":
                    return True
            except Exception:
                pass
        return False

    def _printer_is_paused(self):
        eventtime = self.reactor.monotonic()
        return self.print_stats.get_status(eventtime)["state"] == "paused"

    def _save_power_loss_info(self, is_power_loss=True):
        printing = self._printer_is_printing()
        if not printing:
            self._plr_cleared_by_user = False

        if is_power_loss and printing:
            if self._plr_cleared_by_user:
                self.power_loss_info = {"power_loss_resume": False}
            else:
                eventtime = self.reactor.monotonic()
                # 获取所有温度
                heaters = {}
                if self.pheaters is not None:
                    for heater_name in self.pheaters.get_all_heaters():
                        heater = self.pheaters.lookup_heater(heater_name.split()[-1])
                        temperature, target = heater.get_temp(eventtime)
                        heaters[heater_name] = {
                            "name": heater_name.split()[-1],
                            "temperature": temperature,
                            "target": target,
                        }
                # 获取gcode移动状态
                gcodestatus = self.gcode_move.get_status()
                # 获取打印状态
                printstats = self.print_stats.get_status(eventtime)
                # 获取风扇速度
                fan = self.printer.lookup_object("fan", None)
                # 获取toolhead
                toolhead = self.printer.lookup_object("toolhead", None)
                toolhead_status = None
                if toolhead is not None:
                    toolhead_status = toolhead.get_status(eventtime)
                # 获取dual_carriage
                dual_carriage = self.printer.lookup_object("dual_carriage", None)
                dual_carriage_status = None
                if dual_carriage is not None:
                    dual_carriage_status = dual_carriage.get_status(eventtime)
                if (
                    printstats["filename"] == ""
                    and self.power_loss_info is not None
                    and "print_stats" in self.power_loss_info
                ):
                    printstats = self.power_loss_info["print_stats"]
                current_object = ""
                if self.exclude_objects is not None:
                    current_object = self.exclude_objects.current_object
                fan_speed = 255
                if fan is not None:
                    fan_speed = int(fan.get_status(eventtime)["speed"] * 255)
                # 生成数据
                self.power_loss_info = {
                    "power_loss_resume": True,
                    "is_paused": self._printer_is_paused(),
                    "file_path": self.virtual_sdcard.file_path(),
                    "progress": self.virtual_sdcard.progress(),
                    "is_active": self.virtual_sdcard.is_active(),
                    "file_size": self.virtual_sdcard.file_size,
                    "gcode_move": gcodestatus,
                    "print_stats": printstats,
                    "heaters": heaters,
                    "toolhead": toolhead_status,
                    "dual_carriage": dual_carriage_status,
                    "file_position": self.virtual_sdcard.file_position,
                    "next_file_position": self.virtual_sdcard.next_file_position,
                    "current_object": current_object,
                    "fan_speed": fan_speed,
                    "move_speed_percent": gcodestatus["speed_factor"] * 100,
                    "extrude_speed_percent": gcodestatus["extrude_factor"] * 100,
                }
        else:
            self.power_loss_info = {"power_loss_resume": False}
        try:
            safe = _sanitize_for_json(self.power_loss_info)
            # 完整快照体积大，用 info 每次落盘会严重拖慢主机（易诱发 MCU Timer too close）
            logging.debug("%s", json.dumps(safe, ensure_ascii=False))
            _persist_power_loss_json(self.sdcard_dirname, safe)
        except Exception:
            logging.exception("power_loss_resume: 落盘或日志序列化失败（已忽略，避免中断打印）")

    def _shutdown(self):
        try:
            self.gcode.run_script(self.shutdown_gcode.render())
        except:
            logging.exception("Script running error")
        try:
            if self.is_shutdown:
                self.webhooks.call_remote_method("shutdown_machine")
        except self.printer.command_error:
            logging.exception("Remote Call Error")

    def _power_button_handler(self, eventtime, state):
        if state == 0:
            # 关机
            logging.info("关机")
            self._save_power_loss_info()
            self._shutdown()

    def run_layer_change_gcode(self):
        logging.info("Layer Change Gcode")
        if self.layer_change_gcode is not None and self.layer_change_gcode != "":
            try:
                self.gcode.run_script(
                    self.layer_change_gcode.render(
                        context=self.layer_change_gcode_context
                    )
                )
            except:
                logging.exception("Script running error")

    def _handle_power_loss_resume(self):
        if self.power_loss_info == None:
            self.gcode._respond_error("没有找到续打信息")
            return
        if (
            self.power_loss_info["power_loss_resume"] == False
            or self.power_loss_info["file_path"] == None
        ):
            self.gcode._respond_error("没有需要续打的")
            return
        if (
            "file_path" in self.power_loss_info
            and self.power_loss_info["file_path"] is not None
            and self.power_loss_info["file_path"] != ""
            and "print_stats" in self.power_loss_info
            and self.power_loss_info["print_stats"]["filename"] is not None
            and self.power_loss_info["print_stats"]["filename"] != ""
            and "file_size" in self.power_loss_info
            and "gcode_move" in self.power_loss_info
        ):
            self.gcode.respond_raw("正在恢复打印")
        else:
            self.gcode._respond_error("续打信息不完整")
            return
        self.virtual_sdcard._reset_file()
        # 启用开始打状态，防止升温过程被中断
        # 重新开始的打印预计剩余时间将不准确，切片剩余时间可做参考
        self.print_stats.filename = self.power_loss_info["print_stats"]["filename"]
        self.print_stats.total_duration = self.power_loss_info["print_stats"][
            "total_duration"
        ]
        self.print_stats.filament_used = self.power_loss_info["print_stats"][
            "filament_used"
        ]
        self.print_stats.state = self.power_loss_info["print_stats"]["state"]
        self.print_stats.error_message = self.power_loss_info["print_stats"]["message"]
        self.print_stats.info_total_layer = self.power_loss_info["print_stats"]["info"][
            "total_layer"
        ]
        self.print_stats.info_current_layer = self.power_loss_info["print_stats"][
            "info"
        ]["current_layer"]
        filename = self.power_loss_info["print_stats"]["filename"]
        if filename == None or filename == "":
            filename = os.path.basename(self.power_loss_info["file_path"])
        if filename == None or filename == "":
            self.gcode._respond_error("没有找到续打文件")
            return
        self.print_stats.set_current_file(filename)
        self.print_stats.note_start()

        x = self.power_loss_info["gcode_move"]["gcode_position"][0]
        y = self.power_loss_info["gcode_move"]["gcode_position"][1]
        z = self.power_loss_info["gcode_move"]["gcode_position"][2]
        e = self.power_loss_info["gcode_move"]["gcode_position"][3]

        # 强制设置工具头位置
        toolhead = self.printer.lookup_object("toolhead")
        toolhead.get_last_move_time()
        curpos = toolhead.get_position()
        toolhead.set_position([x, y, z, curpos[3]], homing_axes="xyz")

        # 单独提取挤出与热床温度信息
        extruder = self.power_loss_info["heaters"].get(
            "extruder", {"temp": 0, "target": 0}
        )
        bed = self.power_loss_info["heaters"].get("heater_bed", {"temp": 0, "target": 0})
        # 将断电数据写入jinja2模版参数
        plr = {
            "POS_X": x,
            "POS_Y": y,
            "POS_Z": z,
            "POS_E": e,
            "extruder": extruder,
            "bed": bed,
        }
        plr.update(self.power_loss_info)
        context = self.start_gcode.create_template_context()
        context.update({"PLR": plr})

        if self.layer_change_gcode is not None and self.layer_change_gcode != "":
            self.layer_change_gcode_context = (
                self.layer_change_gcode.create_template_context()
            )
            self.layer_change_gcode_context.update({"PLR": plr})

        # 设置坐标信息
        lines = []
        lines.append(f"G1 F{self.power_loss_info['gcode_move']['speed']}")
        lines.append(f"G90")
        lines.append(f"G1 X{x} Y{y} Z{z}")
        if self.power_loss_info["is_paused"] and self.paused_recover_z > 0.0:
            lines.append(f"G91")
            lines.append(f"G1 Z{self.paused_recover_z}")
        if self.power_loss_info["gcode_move"]["absolute_coordinates"]:
            lines.append("G90")
        else:
            lines.append("G91")
        if self.power_loss_info["gcode_move"]["absolute_extrude"]:
            lines.append("M82")
        else:
            lines.append("M83")
        lines.append(f"G92 E{e}")

        # 执行gcode宏
        try:
            self.gcode.run_script(self.start_gcode.render(context=context))
            if len(lines) > 0:
                for line in lines:
                    self.gcode.run_script(line)
        except:
            logging.exception("Script running error")

        # 调用virtual_sdcard从指定位置加载文件
        try:
            # 设置文件位置
            current_position = self.power_loss_info["file_position"]
            f = io.open(
                self.power_loss_info["file_path"], "r", newline="", errors="ignore"
            )
            self.virtual_sdcard._gcode_file_path = self.power_loss_info["file_path"]
            f.seek(0, os.SEEK_END)
            fsize = f.tell()
            f.seek(self.virtual_sdcard.file_position)
            while current_position > 0:
                current_position -= 1
                f.seek(current_position)
                char = f.read(1)
                # 如果找到了换行符，说明已经找到了前一行的开头位置
                if char == "\n":
                    break
            self.virtual_sdcard.file_position = current_position
        except:
            logging.exception("virtual_sdcard file open")
            self.gcode._respond_error("Unable to open file")
            return
        self.virtual_sdcard.current_file = f
        self.virtual_sdcard.file_size = fsize
        self.virtual_sdcard.current_file.seek(self.virtual_sdcard.file_position)
        self.virtual_sdcard.is_pwr_loss_resume = True
        self.virtual_sdcard.layer_change_count = 0
        self.virtual_sdcard.is_resume_speed = True
        # 开始打印
        self.virtual_sdcard.do_resume()

        # 清除断电数据
        self._save_power_loss_info(False)
        logging.info("开始打印")


def load_config(config):
    return PowerLossResume(config)
