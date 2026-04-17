# Virtual sdcard support (print files directly from a host g-code file)
#
# Copyright (C) 2018-2024  Kevin O'Connor <kevin@koconnor.net>
#
# This file may be distributed under the terms of the GNU GPLv3 license.
import os, sys, logging, io, re, threading, subprocess, json
import psutil

VALID_GCODE_EXTS = ["gcode", "g", "gco"]
LAYER_CHANGE_KEYWORDS = ["; layer #", ";LAYER:", "; layer:", "; LAYER:", ";AFTER_LAYER_CHANGE", ";LAYER_CHANGE"]

DEFAULT_ERROR_GCODE = """
{% if 'heaters' in printer %}
   TURN_OFF_HEATERS
{% endif %}
"""


class VirtualSD:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.printer.register_event_handler("klippy:ready", self._handle_ready)
        # sdcard state
        sd = config.get("path")
        self.sdcard_dirname = os.path.normpath(os.path.expanduser(sd))
        self.current_file = None
        self.file_position = self.file_size = 0
        self.scripts = []
        self.is_from_height = False
        self.from_height: float = None
        self._parse_state = 0
        self._thread_parser = None
        self._gcode_file_path = None
        # Print Stat Tracking
        self.print_stats = self.printer.load_object(config, "print_stats")
        # Power Loss Resume
        self.power_loss_resume =  self.printer.lookup_object("power_loss_resume", None)
        self.is_pwr_loss_resume = False
        self.layer_change_count = 0
        self.is_resume_speed = False
        # Work timer
        self.reactor = self.printer.get_reactor()
        self.must_pause_work = self.cmd_from_sd = False
        self.next_file_position = 0
        self.work_timer = None
        # Error handling
        gcode_macro = self.printer.load_object(config, "gcode_macro")
        self.on_error_gcode = gcode_macro.load_template(
            config, "on_error_gcode", DEFAULT_ERROR_GCODE
        )
        # Register commands
        self.gcode = self.printer.lookup_object("gcode")
        for cmd in ["M20", "M21", "M23", "M24", "M25", "M26", "M27"]:
            self.gcode.register_command(cmd, getattr(self, "cmd_" + cmd))
        for cmd in ["M28", "M29", "M30"]:
            self.gcode.register_command(cmd, self.cmd_error)
        self.gcode.register_command(
            "SDCARD_RESET_FILE",
            self.cmd_SDCARD_RESET_FILE,
            desc=self.cmd_SDCARD_RESET_FILE_help,
        )
        self.gcode.register_command(
            "SDCARD_PRINT_FILE",
            self.cmd_SDCARD_PRINT_FILE,
            desc=self.cmd_SDCARD_PRINT_FILE_help,
        )
        webhooks = self.printer.lookup_object("webhooks")
        webhooks.register_endpoint(
            "virtual_sdcard/from_height_print", self._handle_from_height_print
        )
        self.printer.register_event_handler("klippy:analyze_shutdown",
                                            self._handle_analyze_shutdown)

    def _handle_analyze_shutdown(self, msg, details):
        if self.work_timer is not None:
            self.must_pause_work = True
            if self.current_file is not None:
                try:
                    readpos = max(self.file_position - 1024, 0)
                    readcount = self.file_position - readpos
                    self.current_file.seek(readpos)
                    data = self.current_file.read(readcount + 128)
                except:
                    logging.exception("virtual_sdcard shutdown read")
                    return
                logging.info(
                    "Virtual sdcard (%d): %s\nUpcoming (%d): %s",
                    readpos,
                    repr(data[:readcount]),
                    self.file_position,
                    repr(data[readcount:]),
                )

    def _handle_ready(self):
        self.power_loss_resume =  self.printer.lookup_object("power_loss_resume", None)
        
    def stats(self, eventtime):
        if self.work_timer is None:
            return False, ""
        return True, "sd_pos=%d" % (self.file_position,)

    def get_file_list(self, check_subdirs=False):
        if check_subdirs:
            flist = []
            for root, dirs, files in os.walk(self.sdcard_dirname, followlinks=True):
                for name in files:
                    ext = name[name.rfind(".") + 1 :]
                    if ext not in VALID_GCODE_EXTS:
                        continue
                    full_path = os.path.join(root, name)
                    r_path = full_path[len(self.sdcard_dirname) + 1 :]
                    size = os.path.getsize(full_path)
                    flist.append((r_path, size))
            return sorted(flist, key=lambda f: f[0].lower())
        else:
            dname = self.sdcard_dirname
            try:
                filenames = os.listdir(self.sdcard_dirname)
                return [
                    (fname, os.path.getsize(os.path.join(dname, fname)))
                    for fname in sorted(filenames, key=str.lower)
                    if not fname.startswith(".")
                    and os.path.isfile((os.path.join(dname, fname)))
                ]
            except:
                logging.exception("virtual_sdcard get_file_list")
                raise self.gcode.error("Unable to get file list")

    def get_status(self, eventtime):
        return {
            "file_path": self.file_path(),
            "progress": self.progress(),
            "is_active": self.is_active(),
            "file_position": self.file_position,
            "file_size": self.file_size,
        }

    def file_path(self):
        if self.current_file:
            return self.current_file.name
        return None

    def progress(self):
        if self.file_size:
            return float(self.file_position) / self.file_size
        else:
            return 0.0

    def is_active(self):
        return self.work_timer is not None

    def do_pause(self):
        if self.work_timer is not None:
            self.must_pause_work = True
            self.is_from_height = False
            while self.work_timer is not None and not self.cmd_from_sd:
                self.reactor.pause(self.reactor.monotonic() + 0.001)

    def do_resume(self):
        if self.work_timer is not None:
            raise self.gcode.error("SD busy")
        self.must_pause_work = False
        self.is_from_height = False
        self.work_timer = self.reactor.register_timer(
            self.work_handler, self.reactor.NOW
        )

    def do_cancel(self):
        if self.current_file is not None:
            self.do_pause()
            self.current_file.close()
            self.current_file = None
            self.print_stats.note_cancel()
        self.file_position = self.file_size = 0
        self.is_from_height = False
        self.is_pwr_loss_resume = False
        self.is_resume_speed = False

    # G-Code commands
    def cmd_error(self, gcmd):
        raise gcmd.error("SD write not supported")

    def _reset_file(self):
        self.is_from_height = False
        if self.current_file is not None:
            self.do_pause()
            self.current_file.close()
            self.current_file = None
        self.file_position = self.file_size = 0
        self.is_pwr_loss_resume = False
        self.is_resume_speed = False
        self.print_stats.reset()
        self.printer.send_event("virtual_sdcard:reset_file")

    cmd_SDCARD_RESET_FILE_help = (
        "Clears a loaded SD File. Stops the print " "if necessary"
    )

    def cmd_SDCARD_RESET_FILE(self, gcmd):
        if self.cmd_from_sd:
            raise gcmd.error("SDCARD_RESET_FILE cannot be run from the sdcard")
        self._reset_file()

    cmd_SDCARD_PRINT_FILE_help = (
        "Loads a SD file and starts the print.  May " "include files in subdirectories."
    )

    def cmd_SDCARD_PRINT_FILE(self, gcmd):
        if self.work_timer is not None:
            raise gcmd.error("SD busy")
        self._reset_file()
        filename = gcmd.get("FILENAME")
        if filename[0] == "/":
            filename = filename[1:]
        self._load_file(gcmd, filename, check_subdirs=True, do_resume=True)

    def cmd_M20(self, gcmd):
        # List SD card
        files = self.get_file_list()
        gcmd.respond_raw("Begin file list")
        for fname, fsize in files:
            gcmd.respond_raw("%s %d" % (fname, fsize))
        gcmd.respond_raw("End file list")

    def cmd_M21(self, gcmd):
        # Initialize SD card
        gcmd.respond_raw("SD card ok")

    def cmd_M23(self, gcmd):
        # Select SD file
        if self.work_timer is not None:
            raise gcmd.error("SD busy")
        self._reset_file()
        filename = gcmd.get_raw_command_parameters().strip()
        if filename.startswith("/"):
            filename = filename[1:]
        self._load_file(gcmd, filename)

    def _handle_from_height_print(self, web_request):
        filename = web_request.get_str("filename")
        height = web_request.get_float("height")
        self.from_height = height
        if filename[0] == "/":
            filename = filename[1:]
        self._load_file(self.gcode, filename, check_subdirs=True)
        # 开启多线程解析
        self._parse_state = 1
        self._thread_parser = threading.Thread(target=self._thread_parse_gcode)
        self._thread_parser.start()
        self.is_from_height = True
        self.must_pause_work = False
        self.work_timer = self.reactor.register_timer(
            self.work_handler, self.reactor.NOW
        )
        web_request.send({"msg": "Start load file"})

    def _parse_gcode(self):
        self._parse_state = 1
        gcmd = self.gcode
        height = self.from_height
        gcmd.respond_raw("开始解析gcode")
        try:
            generator = ""
            # 第一次循环
            self.current_file.seek(0)
            line_num = 0
            partial_input = ""
            lines = []
            z_value = None
            old_info = {
                "absolute_extrusion": False,
                "absolute_position": False,
                "x_value": 0.0,
                "y_value": 0.0,
                "e_value": 0.0,
                "z_value": 0.0,
                "f_value": 0.0,
                "fan_speed": 0,
                "extruder_temp": 0.0,
                "bed_temp": 0.0,
            }
            gcmd.respond_raw("识别切片工具")
            while True:
                data = self.current_file.read(1024 * 1024)
                if not data:
                    break
                lines = data.split("\n")
                lines[0] = partial_input + lines[0]
                partial_input = lines.pop()
                lines.reverse()
                # line = self.current_file.readline()
                if len(lines) < 1:
                    continue
                line = lines.pop()
                line = line.strip()
                line_num += 1
                # if not line or len(line) < 2:
                #     continue
                # if line[0:1] == ";":
                #     if "Cura_SteamEngine" in line:
                #         generator = "CURA"
                #         break
                #     elif "OrcaSlicer" in line:
                #         generator = "ORCA"
                #         break
                #     elif "Simplify3D" in line:
                #         generator = "S3D"
                #         break
            if generator is None or generator == "":
                gcmd.error("无法识别切片工具")
                self._parse_state = 2
                return
            gcmd.respond_raw(f"切片工具为: {generator}")
            self.current_file.seek(0)
            line_num = 0
            partial_input = ""
            lines = []
            gcmd.respond_raw("识别元数据")
            while True:
                line = self.current_file.readline()
                line = line.strip()
                line_num += 1
                if not line:
                    continue
                if not line.startswith(";"):
                    cmds = line.upper().split(" ")
                    if len(cmds) > 0:
                        if cmds[0] == "M82":
                            old_info["absolute_extrusion"] = True
                        elif cmds[0] == "M83":
                            old_info["absolute_extrusion"] = False
                        elif cmds[0] == "G90":
                            old_info["absolute_position"] = True
                        elif cmds[0] == "G91":
                            old_info["absolute_position"] = False
                        # elif cmds[0] == "G1" or cmds[0] == "G0":
                        #     if "Z" in line:
                        #         for cmd in cmds:
                        #             if cmd.startswith("Z"):
                        #                 old_info["z_value"] = float(cmd[1:])
                        #                 break
                        # for cmd in cmds:
                        #     if cmd == "G0" or cmd == "G1":
                        #         continue
                        #     if cmd.startswith("X"):
                        #         old_info["x_value"] = float(cmd[1:])
                        #     elif cmd.startswith("Y"):
                        #         old_info["y_value"] = float(cmd[1:])
                        #     elif cmd.startswith("Z"):
                        #         old_info["z_value"] = float(cmd[1:])
                        #     elif cmd.startswith("E"):
                        #         old_info["e_value"] = float(cmd[1:])
                        #     elif cmd.startswith("F"):
                        #         old_info["f_value"] = int(cmd[1:])

                        # match = re.search(r"X([+-]?\d*\.?\d+)", line.upper())
                        # if match:
                        #     old_info["x_value"] = float(match.group(1))
                        # match = re.search(r"Y([+-]?\d*\.?\d+)", line.upper())
                        # if match:
                        #     old_info["y_value"] = float(match.group(1))
                        # match = re.search(r"E([+-]?\d*\.?\d+)", line.upper())
                        # if match:
                        #     old_info["e_value"] = float(match.group(1))
                        # match = re.search(r"Z([+-]?\d*\.?\d+)", line.upper())
                        # if match:
                        #     old_info["z_value"] = float(match.group(1))
                        # match = re.search(r"F([+-]?\d*\.?\d+)", line.upper())
                        # if match:
                        #     old_info["f_value"] = float(match.group(1))
                        elif cmds[0] == "M106":
                            match = re.search(r"S([+-]?\d*\.?\d+)", line.upper())
                            if match:
                                old_info["fan_speed"] = int(match.group(1))
                        elif cmds[0] == "M109" or cmds[0] == "M104":
                            match = re.search(r"S([+-]?\d*\.?\d+)", line.upper())
                            if match:
                                old_info["extruder_temp"] = float(match.group(1))
                        elif cmds[0] == "M190" or cmds[0] == "M140":
                            match = re.search(r"S([+-]?\d*\.?\d+)", line.upper())
                            if match:
                                old_info["bed_temp"] = float(match.group(1))

                # 寻找Z位置
                if generator == "ORCA":
                    if ";LAYER_CHANGE" in line:
                        next_line = self.current_file.readline()
                        if not next_line:
                            continue
                        z_value = float(next_line.split(":")[1])
                elif generator == "CURA":
                    if not line.startswith("G1") and not line.startswith("G0"):
                        continue
                    if "Z" not in line:
                        continue
                    cmds = line.upper().split(" ")
                    for cmd in cmds:
                        if cmd.startswith("Z"):
                            z_value = float(cmd[1:])
                            break
                elif generator == "S3D":
                    if not line.startswith("; layer"):
                        continue
                    zs = line.split("=")
                    if len(zs) == 2:
                        z_value = float(zs[1].strip())
                else:
                    gcmd.error("不支持的切片")
                    self._parse_state = 2
                    return
                # 检查Z轴位置
                if not z_value:
                    continue
                if height == z_value or (
                    height - z_value <= 0.1 and height - z_value > 0
                ):
                    gcmd.respond_raw(f"找到位置, Z: {z_value}, 行: {line_num}")
                    gcmd.respond_raw(
                        f"最后位置: X:{old_info['x_value']}, Y:{old_info['y_value']}, Z:{old_info['z_value']}, E:{old_info['e_value']}"
                    )
                    gcmd.respond_raw(
                        f"绝对挤出: {old_info['absolute_extrusion']}, 绝对位置: {old_info['absolute_position']}"
                    )
                    gcmd.respond_raw(
                        f"最后热床温度: {old_info['bed_temp']}, 最后风扇转速: {old_info['fan_speed']}, 最后挤出温度: {old_info['extruder_temp']}"
                    )
                    self.scripts = []

                    if old_info["extruder_temp"]:
                        self.scripts.append(f"M109 S{old_info['extruder_temp']}")
                    if old_info["bed_temp"]:
                        self.scripts.append(f"M190 S{old_info['bed_temp']}")
                    if old_info["fan_speed"]:
                        self.scripts.append(f"M106 S{old_info['fan_speed']}")
                    if old_info["absolute_extrusion"]:
                        self.scripts.append("M82")
                    else:
                        self.scripts.append("M83")
                    if old_info["absolute_position"]:
                        self.scripts.append("G90")
                    else:
                        self.scripts.append("G91")
                    self.file_position = self.current_file.tell()
                    self._parse_state = 3
                    return
                elif z_value - height > 0.2:
                    logging.info("找不到位置")
        except Exception as e:
            logging.exception(f"virtual_sdcard parse_gcode: {e}")
            gcmd.error("解析gcode发生错误")
        self._parse_state = 2
        return

    def _thread_parse_gcode(self):
        self._parse_state = 1
        if not self._gcode_file_path or not self.from_height:
            self._parse_state = 2
            return
        gcmd = self.gcode

        gcmd.respond_raw(f"开始解析gcode: {self._gcode_file_path}")
        command = ["parse_gcode", self._gcode_file_path, str(self.from_height)]
        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,  # 将标准错误重定向到标准输出
                shell=False,  # 如果你使用的是shell命令
            )
            output, _ = process.communicate()  # 等待命令执行完成
            logging.info(output)
            if process.returncode != 0:
                self._parse_state = 2
                return
            ret = output.decode().strip().replace("\n", "")
            if not ret or len(ret) < 4:
                gcmd._respond_error("解析gcode失败")
                self._parse_state = 2
                return
        except Exception as e:
            logging.exception(f"virtual_sdcard parse_gcode: {e}")
            gcmd._respond_error("解析gcode发生错误")
            self._parse_state = 2
            return
        try:
            jd = json.loads(ret)
            if not jd:
                gcmd._respond_error("解析gcode返回发生错误")
                self._parse_state = 2
                return
            if jd["code"] != 0 or not jd["data"]:
                gcmd._respond_error(f"解析gcode错误: {jd['msg']}")
                self._parse_state = 2
                return
            gcmd.respond_raw(
                f"找到位置, Z: {jd['data']['height']}, 行: {jd['data']['line']}"
            )
            gcmd.respond_raw(
                f"最后热床温度: {jd['data']['bed_temp']}, 最后风扇转速: {jd['data']['fan_speed']}, 最后挤出温度: {jd['data']['extruder_temp']}"
            )
            self.scripts = []

            if jd["data"]["extruder_temp"]:
                self.scripts.append(f"M109 S{jd['data']['extruder_temp']}")
            if jd["data"]["bed_temp"]:
                self.scripts.append(f"M190 S{jd['data']['bed_temp']}")
            if jd["data"]["fan_speed"]:
                self.scripts.append(f"M106 S{jd['data']['fan_speed']}")
            if jd["data"]["absolute_extrusion"]:
                self.scripts.append("M82")
            else:
                self.scripts.append("M83")
            if jd["data"]["absolute_position"]:
                self.scripts.append("G90")
            else:
                self.scripts.append("G91")
            self.file_position = jd["data"]["seek"]
            self._parse_state = 3
            return
        except Exception as e:
            logging.exception(f"virtual_sdcard parse_gcode: {e}")
            gcmd._respond_error("解析gcode返回发生错误")
            self._parse_state = 2
            return

        self._parse_state = 2
        return

    def _get_mount_point(self, path):
        path = os.path.abspath(path)
        mount_points = sorted(
            psutil.disk_partitions(all=True),
            key=lambda p: len(p.mountpoint),
            reverse=True
        )
        for part in mount_points:
            if path == part.mountpoint or path.startswith(part.mountpoint.rstrip('/') + '/'):
                return part
        return None

    def _get_base_device(self, dev_path):
        dev_name = os.path.basename(dev_path)
        m = re.match(r'^(?P<base>.+)p[0-9]+$', dev_name)
        if m:
            return f"/dev/{m.group('base')}"
        m = re.match(r'^(?P<base>[a-zA-Z]+)[0-9]+$', dev_name)
        if m:
            return f"/dev/{m.group('base')}"
        return dev_path

    def _is_removable_device(self, dev_path):
        base = self._get_base_device(dev_path)
        dev_name = os.path.basename(base)
        removable_path = f"/sys/block/{dev_name}/removable"
        try:
            with open(removable_path) as f:
                return f.read().strip() == "1"
        except FileNotFoundError:
            return False

    def _load_file(self, gcmd, filename, check_subdirs=False, do_resume=False):
        files = self.get_file_list(check_subdirs)
        flist = [f[0] for f in files]
        files_by_lower = {fname.lower(): fname for fname, fsize in files}
        fname = filename
        try:
            if fname not in flist:
                fname = files_by_lower[fname.lower()]
            fname = os.path.join(self.sdcard_dirname, fname)
            # Check if it is a removable disk file.
            mount = self._get_mount_point(fname)
            if mount is None:
                logging.exception(f"virtual_sdcard file open: {fname}")
                raise gcmd.error("Not found file on removable device")
            if self._is_removable_device(mount.device):
                self._load_removable_file(gcmd, filename, fname, do_resume)
                return

            f = io.open(fname, "r", newline="", errors="ignore")
            self._gcode_file_path = fname
            f.seek(0, os.SEEK_END)
            fsize = f.tell()
            f.seek(0)
        except:
            logging.exception("virtual_sdcard file open")
            raise gcmd.error("Unable to open file")
        gcmd.respond_raw("File opened:%s Size:%d" % (filename, fsize))
        gcmd.respond_raw("File selected")
        self.current_file = f
        self.file_position = 0
        self.file_size = fsize
        self.print_stats.set_current_file(filename)
        # start printing
        if do_resume:
            self.do_resume()

    def _load_removable_file(self, gcmd, filename, fname, do_resume):
        gcmd.respond_raw(f"external files: {fname}")
        if not os.path.exists(os.path.join(self.sdcard_dirname, ".UDISK")):
            os.mkdir(os.path.join(self.sdcard_dirname, ".UDISK"))
        new_fname = os.path.join(self.sdcard_dirname, ".UDISK/tmp.gcode")
        try:
            # copy to local dir
            def _copy_file_thread(src, dst, callback, progress_callback=None, chunk_size=1024*1024*10):
                total_size = os.path.getsize(src)
                copied = 0
                try:
                    with open(src, "rb") as fsrc, open(dst, "wb") as fdst:
                        while True:
                            chunk = fsrc.read(chunk_size)
                            if not chunk:
                                break
                            fdst.write(chunk)
                            if progress_callback:
                                copied += len(chunk)
                                progress_callback(copied, total_size)
                        fdst.flush()
                        os.fsync(fdst.fileno())
                except Exception as e:
                    callback(success=False, dst=dst, error=e)
                    return
                callback(success=True, dst=dst, error=None)

            def _on_copy_finished(success, dst, error):
                if success:
                    gcmd.respond_raw(f"Copy files from removable disk completed: {dst}")
                    self._reset_file()
                    f = io.open(dst, 'r', newline='')
                    f.seek(0, os.SEEK_END)
                    fsize = f.tell()
                    f.seek(0)
                    gcmd.respond_raw("File opened:%s Size:%d" % (filename, fsize))
                    gcmd.respond_raw("File selected")
                    self.current_file = f
                    self.file_position = 0
                    self.file_size = fsize
                    self.print_stats.set_current_file(filename)
                    if do_resume:
                        self.do_resume()
                    return
                else:
                    logging.exception(f"An error occurred during file copy: {error}")
                    raise gcmd.respond_raw("copy file failed")

            def _on_copy_progress(copied, total_size):
                    percent = (copied / total_size) * 100
                    percent_int = int(percent // 5) * 5
                    if not hasattr(_on_copy_progress, "last_printed"):
                        _on_copy_progress.last_printed = -1
                    if percent_int != _on_copy_progress.last_printed:
                        _on_copy_progress.last_printed = percent_int
                        gcmd.respond_raw(f"Copying file: {percent_int}%")

            threading.Thread(
                target=_copy_file_thread,
                args=(fname, new_fname, _on_copy_finished, _on_copy_progress),
                daemon=True
            ).start()

            gcmd.respond_raw("copy file started")
            self.print_stats.set_current_file(filename)
            self.print_stats.note_start()
            return
        except FileNotFoundError:
            logging.exception(f"Source file not found: {fname}")
            raise gcmd.error(f"Source file not found: {fname}")
        except PermissionError:
            logging.exception("Permission denied")
            raise gcmd.error("Permission denied")
        except Exception as e:
            logging.exception(f"An error occurred: {e}")
            raise gcmd.error("copy file failed")

    def cmd_M24(self, gcmd):
        # Start/resume SD print
        self.do_resume()

    def cmd_M25(self, gcmd):
        # Pause SD print
        self.do_pause()

    def cmd_M26(self, gcmd):
        # Set SD position
        if self.work_timer is not None:
            raise gcmd.error("SD busy")
        pos = gcmd.get_int("S", minval=0)
        self.file_position = pos

    def cmd_M27(self, gcmd):
        # Report SD print status
        if self.current_file is None:
            gcmd.respond_raw("Not SD printing.")
            return
        gcmd.respond_raw(
            "SD printing byte %d/%d" % (self.file_position, self.file_size)
        )

    def get_file_position(self):
        return self.next_file_position

    def set_file_position(self, pos):
        self.next_file_position = pos

    def is_cmd_from_sd(self):
        return self.cmd_from_sd
    
    def is_layer_change(self, line):
        if line.startswith(";"):
            for layer_key in LAYER_CHANGE_KEYWORDS:
                if line.startswith(layer_key):
                    self.layer_change_count += 1
                    self.reactor.pause(self.reactor.monotonic() + 0.001)
                    return True
        return False
    
    # Background work timer
    def work_handler(self, eventtime):
        if self.is_from_height:
            idle_timeout = self.printer.lookup_object("idle_timeout")
            if self.print_stats.get_status(eventtime)["state"] != "printing":
                self.print_stats.note_start()
            if self._parse_state == 1:
                idle_timeout.state = "Printing"
                return eventtime + 0.1
            elif self._parse_state == 2:
                logging.info("文件解析失败")
                self.gcode._respond_error("文件解析失败")
                self.is_from_height = False
                idle_timeout.state = "Idle"
                self.work_timer = None
                self._reset_file()
                return self.reactor.NEVER
            elif self._parse_state == 3:
                self.is_from_height = True
                logging.info("文件解析完成")
                self.gcode.respond_raw("文件解析完成")

        logging.info("Starting SD card print (position %d)", self.file_position)
        self.reactor.unregister_timer(self.work_timer)
        try:
            self.current_file.seek(self.file_position)
        except:
            logging.exception("virtual_sdcard seek")
            self.work_timer = None
            return self.reactor.NEVER
        if self.print_stats.get_status(eventtime)["state"] != "printing":
            self.print_stats.note_start()
        gcode_mutex = self.gcode.get_mutex()
        partial_input = ""
        lines = []
        error_message = None
        while not self.must_pause_work:
            if not lines:
                # Read more data
                try:
                    data = self.current_file.read(8192)
                except:
                    logging.exception("virtual_sdcard read")
                    break
                if not data:
                    # End of file
                    self.current_file.close()
                    self.current_file = None
                    if self.power_loss_resume is not None:
                        self.power_loss_resume._save_power_loss_info(False)
                    logging.info("Finished SD card print")
                    self.gcode.respond_raw("Done printing file")
                    break
                lines = data.split("\n")
                lines[0] = partial_input + lines[0]
                partial_input = lines.pop()
                lines.reverse()
                self.reactor.pause(self.reactor.NOW)
                continue
            # Pause if any other request is pending in the gcode class
            if gcode_mutex.test():
                self.reactor.pause(self.reactor.monotonic() + 0.050)
                continue
            # Dispatch command
            self.cmd_from_sd = True
            if self.scripts and len(self.scripts) > 0:
                line = self.scripts.pop()
                next_file_position = self.file_position
                self.next_file_position = next_file_position
            else:
                line = lines.pop()
                if sys.version_info.major >= 3:
                    next_file_position = self.file_position + len(line.encode()) + 1
                else:
                    next_file_position = self.file_position + len(line) + 1
                self.next_file_position = next_file_position
            if self.is_pwr_loss_resume and self.power_loss_resume is not None:
                self.is_layer_change(line)
                if self.is_resume_speed and self.layer_change_count >= self.power_loss_resume.layer_count:
                    self.is_resume_speed = False
                    # 设置风扇及打印速度
                    self.power_loss_resume.run_layer_change_gcode()
            try:
                self.gcode.run_script(line)
            except self.gcode.error as e:
                error_message = str(e)
                if self.power_loss_resume is not None:
                    self.power_loss_resume._save_power_loss_info()
                try:
                    self.gcode.run_script(self.on_error_gcode.render())
                except:
                    logging.exception("virtual_sdcard on_error")
                break
            except:
                logging.exception("virtual_sdcard dispatch")
                break
            self.cmd_from_sd = False
            self.file_position = self.next_file_position
            # Do we need to skip around?
            if self.next_file_position != next_file_position:
                try:
                    self.current_file.seek(self.file_position)
                except:
                    logging.exception("virtual_sdcard seek")
                    self.work_timer = None
                    return self.reactor.NEVER
                lines = []
                partial_input = ""
        logging.info("Exiting SD card print (position %d)", self.file_position)
        if self.power_loss_resume is not None and not self.must_pause_work:
            self.power_loss_resume._save_power_loss_info()
        self.work_timer = None
        self.cmd_from_sd = False
        if error_message is not None:
            self.print_stats.note_error(error_message)
        elif self.current_file is not None:
            self.print_stats.note_pause()
        else:
            self.print_stats.note_complete()
            if self.power_loss_resume is not None:
                self.power_loss_resume._save_power_loss_info(False)
        return self.reactor.NEVER


def load_config(config):
    return VirtualSD(config)
