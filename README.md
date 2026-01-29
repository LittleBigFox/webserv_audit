# webserv_audit.sh

Universal Linux Web Server Audit Script

## Overview

`webserv_audit.sh` is a standalone shell script that generates a comprehensive audit report for any Linux web server (Debian/Ubuntu), including:
- System information (CPU, RAM, disks, swap, load, IO)
- Apache configuration and status (MPM, includes, workers)
- PHP configuration (version, SAPI, FPM pools, opcache, memory, pool overrides)
- MariaDB/MySQL configuration and status (key variables, buffer pool, status, top tables, profiling)
- Apache/MySQL cross-checks to detect misconfigurations
- Automatic optimization suggestions

The script does not collect or display any personal or confidential data. It is safe to use on any compatible Linux server.

The script can be used with any AI Assistant if necessary, for faster analysis.

## Usage

```bash
wget https://raw.githubusercontent.com/LittleBigFox/webserv_audit/main/webserv_audit.sh
chmod +x webserv_audit.sh
sudo ./webserv_audit.sh [output_file_path]
```
- By default, the report is written to `/webserv/webserv_audit.log` (can be changed via argument or OUT variable).
- Requires sudo/root privileges to access all system information.

## Main Features
- System audit: load, memory, disks, IO
- Apache audit: version, MPM, workers, includes, memory estimation
- PHP audit: version, SAPI, FPM pools, opcache, pool overrides, FPM memory
- MySQL/MariaDB audit: key variables, status, buffer pool, top tables, query profiling, unused indexes
- Automatic optimization suggestions
- No data sent anywhere, no personal data collected

## Compatibility
- Tested on Debian 10/11/12/13 and Ubuntu 20.04/22.04
- Apache2, PHP-FPM, MariaDB/MySQL

## License

MIT. See LICENSE file.

## Author

[LittleBigFox](https://github.com/LittleBigFox)

Contributions and suggestions welcome!
