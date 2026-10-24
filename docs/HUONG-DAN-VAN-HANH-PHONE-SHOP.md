# Hướng dẫn đầy đủ về hạ tầng và vận hành Phone Shop

Tài liệu này mô tả toàn bộ những gì đã cấu hình trên VM Ubuntu cho Phone Shop, cách các thành phần nối với nhau, cách kiểm tra từng phần và cách dựng lại cấu hình bằng Ansible.

CI/CD chỉ là một phần của hệ thống. VM hiện còn đảm nhiệm web, API, database, reverse proxy, kiểm thử trình duyệt, gửi Telegram, firewall, log và backup.

## 1. Trạng thái hiện tại

Hệ thống đã có các phần sau:

- VM Ubuntu chạy trong VMware Workstation, card mạng `ens33` dùng Bridged và hiện có IP `192.168.100.4/24`.
- SSH bằng khóa công khai từ Windows vào Ubuntu.
- Git lưu hai repo: mã nguồn `Phone-shop` và cấu hình `infra_automation`.
- Ansible tự cài gói, tạo database, sinh cấu hình, build mã nguồn và tạo dịch vụ.
- Java 17 và Maven dùng để build/chạy Spring Boot.
- Node.js 22 và npm dùng để build/chạy Next.js và Playwright.
- MySQL lưu dữ liệu trong database `phoneshop_db` với tài khoản riêng của ứng dụng.
- Nginx nhận truy cập ở cổng 80 rồi chuyển `/` tới Next.js và `/api`, `/uploads` tới Spring Boot.
- systemd tự khởi động backend, frontend, Nginx, MySQL và GitHub runner cùng VM.
- UFW chỉ cho kết nối vào các cổng SSH, HTTP và HTTPS.
- systemd journal lưu log và được giới hạn tối đa 500 MB, thời gian giữ tối đa 14 ngày.
- MySQL được nén và sao lưu tự động lúc 02:00 hằng ngày, giữ 14 ngày.
- Playwright chạy tự động lúc 07:00 hằng ngày và gửi kết quả tới Telegram.
- GitHub lưu mã nguồn Phone Shop.
- GitHub Actions tự build Spring Boot bằng Java 17.
- GitHub Actions tự build Next.js bằng Node.js 22.
- GitHub Actions runner tên `phone-shop-vm` chạy trong Ubuntu.
- Khi push vào nhánh `main` và hai bước build thành công, runner tự gọi Ansible để triển khai đúng commit vừa kiểm tra.

Ngày 24/10/2026, máy đã được kiểm tra trực tiếp:

- `ens33` đang UP với IP `192.168.100.4/24`.
- Backend, frontend, Nginx, MySQL và GitHub runner đều `active` và `enabled`.
- Web và API đều trả HTTP `200` sau khi ứng dụng khởi động xong.
- Timer backup đã chạy bù sau khi bật VM và đặt lần kế tiếp lúc 02:00 ngày 25/10/2026.
- Timer Playwright đã chạy bù sau khi bật VM và đặt lần kế tiếp lúc 07:00 ngày 25/10/2026.
- Lần Playwright mới nhất có `36 passed`, `8 failed`, `1 flaky`. Bộ máy tự chạy test và báo lỗi đang hoạt động; tám ca lỗi là vấn đề cần phân tích trong ứng dụng hoặc dữ liệu test.

Lần chạy CI/CD đầu tiên đã thành công tại:

<https://github.com/thoa2005/Phone-shop/actions/runs/39987402072>

## 2. Sơ đồ toàn bộ hệ thống

```text
Windows / máy trong cùng mạng
  |  SSH :22                        Trình duyệt :80
  |                                      |
  +----------------------+---------------+
                         v
                VM Ubuntu 192.168.100.4
                         |
                     Nginx :80
                 +-------+--------+
                 |                |
              /, trang web     /api, /uploads
                 |                |
          Next.js :3000     Spring Boot :8081
                                  |
                              MySQL :3306

systemd trong VM:
  |-- tự khởi động các dịch vụ trên
  |-- 02:00 chạy backup MySQL
  |-- 07:00 chạy Playwright và gửi Telegram
  +-- chạy GitHub Actions self-hosted runner

git push origin main
  -> GitHub Actions build backend + frontend
  -> runner trong VM nhận job Deploy
  -> Ansible triển khai đúng commit đã build
  -> kiểm tra web và API
```

GitHub không SSH từ Internet vào IP riêng `192.168.100.4`. Runner trong VM chủ động kết nối ra GitHub bằng HTTPS, nhận job rồi chạy triển khai tại chỗ.

## 3. Vai trò của từng công nghệ

- **VMware Workstation**: cung cấp máy tính ảo Ubuntu chạy trên Windows.
- **Ubuntu**: hệ điều hành máy chủ của bài lab.
- **Bridged network**: cho VM xuất hiện như một máy riêng trong mạng LAN, nên Windows và máy khác trong mạng có thể SSH hoặc mở web bằng IP của VM.
- **SSH**: điều khiển Ubuntu từ xa qua terminal.
- **tmux**: giữ phiên terminal trên Ubuntu và cho nhiều người cùng nhìn một phiên; tmux không phải công cụ triển khai.
- **Git/GitHub**: lưu lịch sử mã nguồn và cấu hình hạ tầng.
- **Ansible**: đọc playbook YAML rồi đưa máy về trạng thái mong muốn; chạy lại được khi cần dựng hoặc sửa cấu hình.
- **systemd**: quản lý tiến trình và lịch chạy trong Ubuntu.
- **Nginx**: cổng vào duy nhất của web, chuyển yêu cầu đến đúng frontend hoặc backend.
- **Spring Boot**: backend cung cấp API và nghiệp vụ.
- **Next.js**: frontend hiển thị giao diện.
- **MySQL**: lưu dữ liệu lâu dài.
- **Playwright**: giả lập trình duyệt để kiểm thử quy trình người dùng.
- **Telegram bot**: nhận kết quả kiểm thử tự động.
- **GitHub Actions runner**: nhận job CD từ GitHub và triển khai trong VM.
- **UFW**: firewall của Ubuntu.

## 4. Các file tự động hóa quan trọng

### Repo Phone Shop

File `.github/workflows/ci-cd.yml` định nghĩa pipeline:

- `on.push.branches: main`: chạy khi có push vào `main`.
- `on.pull_request.branches: main`: chạy CI khi có pull request vào `main`.
- Job `backend`: chạy Maven `verify`.
- Job `frontend`: chạy `npm ci` và `npm run build`.
- Job `deploy`: chỉ chạy với sự kiện push vào `main`, sau khi backend và frontend thành công.
- `runs-on: [self-hosted, linux, x64, phone-shop]`: chọn đúng runner trong VM.
- `GITHUB_SHA`: mã 40 ký tự xác định chính xác commit đang được triển khai.

Pull request chỉ build để kiểm tra. Pull request không chạy job Deploy.

### Repo hạ tầng

- `ansible/playbooks/phone-shop-prereqs.yml`: cài Java, Maven, Node.js, npm, MySQL, Git, curl, Playwright và Chromium.
- `ansible/playbooks/phone-shop-deploy.yml`: tạo database/tài khoản MySQL, sinh bí mật, lấy mã nguồn, build ứng dụng, tạo service và cấu hình Nginx.
- `ansible/playbooks/phone-shop-monitor.yml`: cài script Playwright, Telegram và timer 07:00.
- `ansible/playbooks/phone-shop-operations.yml`: cấu hình múi giờ, UFW, giới hạn log và timer backup 02:00.
- `ansible/playbooks/phone-shop-cicd.yml`: tải, đăng ký và chạy GitHub Actions runner bằng systemd; cài script deploy và quy tắc sudo.
- `ansible/files/deploy-phone-shop.sh`: khóa để không cho hai lần deploy chạy đồng thời, cập nhật repo hạ tầng, chạy Ansible và kiểm tra HTTP.
- `ansible/files/run-phone-shop-e2e.sh`: chạy test, tóm tắt kết quả và gọi Telegram API.
- `ansible/files/backup-phone-shop.sh`: dump MySQL, nén file và xóa backup quá 14 ngày.
- `ansible/templates/`: mẫu cấu hình Nginx, systemd service, timer và file môi trường.
- `ansible/requirements.yml`: collection Ansible cần thêm để quản lý MySQL, UFW và múi giờ.
- `ansible/inventory/hosts.ini`: cho Ansible biết máy nào cần cấu hình.

Các file bí mật nằm trong `~/.config/infra/` và `/etc/phone-shop/` trên VM. Chúng không được lưu trong Git.

## 5. Kiểm tra nhanh mỗi ngày

### Bước 1: Kiểm tra trên GitHub

Mở:

<https://github.com/thoa2005/Phone-shop/actions>

Một pipeline tốt phải có ba dấu xanh:

1. `Build Spring Boot`
2. `Build Next.js`
3. `Deploy production VM`

Nhấn vào một job để xem từng câu lệnh và lỗi nếu có.

### Bước 2: Kiểm tra runner trong Ubuntu

SSH vào VM rồi chạy:

```bash
systemctl status actions.runner.thoa2005-Phone-shop.phone-shop-vm.service --no-pager
```

Giải thích:

- `systemctl status`: xem trạng thái một dịch vụ systemd.
- `--no-pager`: in kết quả thẳng ra terminal, không mở màn hình cuộn riêng.
- Kết quả cần có `Active: active (running)` và `Listening for Jobs`.

Kiểm tra ngắn gọn:

```bash
systemctl is-active actions.runner.thoa2005-Phone-shop.phone-shop-vm.service
systemctl is-enabled actions.runner.thoa2005-Phone-shop.phone-shop-vm.service
```

- `is-active` cần trả về `active`.
- `is-enabled` cần trả về `enabled`, nghĩa là runner tự chạy khi Ubuntu khởi động.

### Bước 3: Kiểm tra dịch vụ ứng dụng

```bash
systemctl is-active phone-shop-backend phone-shop-frontend nginx mysql
```

Cả bốn dòng cần là `active`.

Muốn xem chi tiết:

```bash
systemctl status phone-shop-backend phone-shop-frontend nginx mysql --no-pager
```

### Bước 4: Kiểm tra HTTP bên trong VM

```bash
curl -I http://127.0.0.1/
curl -sS -o /dev/null -w 'web=%{http_code}\n' http://127.0.0.1/
curl -sS -o /dev/null -w 'api=%{http_code}\n' http://127.0.0.1/api/products
```

Giải thích:

- `curl`: gửi yêu cầu HTTP.
- `-I`: chỉ lấy HTTP header.
- `-sS`: ẩn tiến trình nhưng vẫn hiện lỗi.
- `-o /dev/null`: bỏ nội dung trang vì chỉ cần mã trạng thái.
- `-w`: in thông tin theo định dạng chỉ định.
- Web và API đều cần trả về `200`.

### Bước 5: Kiểm tra từ Windows

Trong PowerShell:

```powershell
curl.exe -I http://192.168.100.4/
Test-NetConnection 192.168.100.4 -Port 80
Test-NetConnection 192.168.100.4 -Port 22
```

Giải thích:

- `curl.exe -I`: kiểm tra Nginx từ bên ngoài VM.
- `Test-NetConnection ... -Port 80`: kiểm tra cổng web.
- `Test-NetConnection ... -Port 22`: kiểm tra cổng SSH.
- `TcpTestSucceeded : True` nghĩa là kết nối được.

Mở trình duyệt:

<http://192.168.100.4/>

### Bước 6: Kiểm tra mạng, cổng và firewall

Trong Ubuntu:

```bash
ip -4 -brief addr show ens33
ss -ltn | grep -E ':(22|80|3000|3306|8081)[[:space:]]'
sudo ufw status verbose
```

Giải thích:

- `ip -4 -brief addr show ens33`: xem IPv4 của card mạng VM. Kết quả hiện tại là `192.168.100.4/24`.
- `ss -ltn`: liệt kê cổng TCP đang lắng nghe.
- `grep -E`: chỉ giữ các cổng cần quan tâm.
- Cổng `22` và `80` phải nhận kết nối từ mạng LAN.
- Cổng `3000`, `8081` và `3306` chỉ nên gắn vào `127.0.0.1`, nên máy ngoài không truy cập trực tiếp được.
- `ufw status verbose`: kiểm tra firewall; chính sách kết nối vào mặc định phải là `deny`, với ngoại lệ OpenSSH và Nginx Full.

`ens33` hiện lấy IP bằng DHCP. IP có thể thay đổi khi router cấp địa chỉ khác; Ansible không làm IP DHCP trở thành IP tĩnh.

### Bước 7: Kiểm tra phần mềm đã cài

```bash
java -version
mvn -version
node --version
npm --version
mysql --version
cd ~/Phone-shop
npx playwright --version
ansible --version
nginx -v
```

Ngày 24/10/2026, máy đang có Java 17, Maven 3.9.12, Node.js 22.22.1, npm 9.2.0, MySQL 8.4.11 và Playwright 1.64.1.

### Bước 8: Phân biệt `active` với `ready`

Ngay sau khi bật VM, systemd có thể báo service là `active` trong khi Java và Next.js vẫn đang khởi tạo. Lần kiểm tra ngày 24/10/2026 cho thấy Spring Boot cần khoảng 23 giây và Next.js cần khoảng 18 giây. Trong khoảng đó Nginx có thể trả `502` tạm thời.

Hãy chờ khoảng 30 đến 60 giây rồi dùng hai lệnh HTTP ở Bước 4. Chỉ khi web và API trả `200` thì ứng dụng mới thật sự sẵn sàng.

## 6. Kiểm tra CI/CD bằng một commit không đổi file

Đây là cách an toàn để chứng minh pipeline tự chạy mà không sửa mã nguồn.

Trong PowerShell:

```powershell
cd D:\Infra\Phone-shop
git status -sb
git commit --allow-empty -m "Test CI CD pipeline"
git push origin main
```

Giải thích:

- `git status -sb`: xem nhánh và thay đổi hiện tại theo dạng ngắn.
- `git commit --allow-empty`: tạo commit dù không có file thay đổi.
- `-m`: đặt nội dung mô tả commit.
- `git push origin main`: gửi commit lên nhánh `main` của GitHub và kích hoạt workflow.

Sau khi push:

1. Mở trang Actions.
2. Xem hai job build chạy trên GitHub.
3. Xem job Deploy chuyển từ `Queued` sang `In progress`, rồi `Success`.
4. Kiểm tra commit trên VM:

```bash
git -C ~/Phone-shop rev-parse --short HEAD
```

Mã ngắn in ra phải trùng với commit trên trang GitHub Actions.

## 7. Xem log

### Log runner

```bash
sudo journalctl -u actions.runner.thoa2005-Phone-shop.phone-shop-vm.service -n 100 --no-pager
```

- `journalctl -u`: lọc log theo tên systemd service.
- `-n 100`: lấy 100 dòng gần nhất.

Theo dõi log mới theo thời gian thực:

```bash
sudo journalctl -fu actions.runner.thoa2005-Phone-shop.phone-shop-vm.service
```

Nhấn `Ctrl+C` để dừng theo dõi.

### Log backend

```bash
sudo journalctl -u phone-shop-backend -n 100 --no-pager
```

### Log frontend

```bash
sudo journalctl -u phone-shop-frontend -n 100 --no-pager
```

### Log Nginx

```bash
sudo journalctl -u nginx -n 100 --no-pager
sudo tail -n 100 /var/log/nginx/error.log
```

## 8. Kiểm tra lịch tự động

```bash
systemctl list-timers phone-shop-backup.timer phone-shop-e2e.timer --all
```

Kết quả cần hiển thị:

- `phone-shop-backup.timer`: lần chạy tiếp theo khoảng 02:00.
- `phone-shop-e2e.timer`: lần chạy tiếp theo khoảng 07:00.

Hai timer có `Persistent=true`. Nếu VM đang tắt đúng giờ chạy, systemd sẽ chạy bù sau lần bật máy tiếp theo. Trong lúc Playwright đang chạy, cột `NEXT` của timer có thể hiện `-`; xem `phone-shop-e2e.service` để biết test còn chạy hay đã xong.

Xem kết quả gần nhất:

```bash
sudo journalctl -u phone-shop-backup.service -n 50 --no-pager
sudo journalctl -u phone-shop-e2e.service -n 100 --no-pager
```

`phone-shop-e2e.service` là service kiểu `oneshot`. Sau khi test xong, trạng thái của nó có thể là `inactive` khi tất cả test đạt hoặc `failed` khi có test lỗi. Trạng thái `failed` trong trường hợp này có nghĩa Playwright trả exit code khác 0; timer vẫn có thể hoạt động bình thường và tiếp tục chạy vào ngày hôm sau.

Xem riêng kết quả tóm tắt Playwright:

```bash
sudo journalctl -u phone-shop-e2e.service --no-pager | grep -E '[0-9]+ (passed|failed|flaky|skipped)' | tail -n 10
```

Kết quả gần nhất ngày 24/10/2026 là 36 đạt, 8 lỗi và 1 chập chờn. Xem log đầy đủ để biết tên từng test lỗi; báo cáo này cũng được gửi tới Telegram.

Kiểm tra file backup:

```bash
sudo ls -lh /var/backups/phone-shop/
```

Kiểm tra file backup có thực sự giải nén được:

```bash
sudo gzip -t /var/backups/phone-shop/ten-file-backup.sql.gz
```

Lệnh không in lỗi và trả về terminal nghĩa là cấu trúc gzip hợp lệ. Việc khôi phục thử vào một database riêng vẫn là phép kiểm tra tốt nhất cho backup.

## 9. Dựng lại cấu hình trên một VM Ubuntu mới

Hiện tại Ansible tự cấu hình hệ điều hành và ứng dụng, nhưng chưa tự tạo VM VMware. Bạn vẫn phải tạo VM Ubuntu mới, tạo user và thiết lập mạng/SSH trước.

### Phần làm thủ công một lần

1. Tạo VM Ubuntu trong VMware Workstation.
2. Chọn card mạng Bridged nếu muốn máy trong LAN truy cập VM.
3. Tạo tài khoản `vanthoa` hoặc sửa biến `app_user` trong các playbook nếu dùng tên khác.
4. Cài SSH server và thêm public key của máy điều khiển.
5. Cấp cho VM quyền đọc repo GitHub qua SSH.
6. Clone repo `infra_automation` vào `/home/vanthoa/infra_automation`.

### Cài Ansible và collection

```bash
sudo apt update
sudo apt install --no-install-recommends ansible-core
cd ~/infra_automation
ansible-galaxy collection install -r ansible/requirements.yml
```

- `apt update`: cập nhật danh sách gói.
- `apt install`: cài Ansible trên VM.
- `--no-install-recommends`: bỏ các gói đề xuất không bắt buộc.
- `ansible-galaxy collection install`: cài module quản lý MySQL, UFW và múi giờ mà playbook sử dụng.

### Chạy playbook theo thứ tự

```bash
cd ~/infra_automation
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-prereqs.yml -K
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-deploy.yml -K
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-operations.yml -K
```

Trong các lệnh trên:

- `ansible-playbook`: thực thi file YAML.
- `-i ansible/inventory/hosts.ini`: chọn danh sách máy đích. Inventory hiện trỏ đến `localhost`, nên Ansible cấu hình chính VM đang chạy lệnh.
- `-K`: hỏi mật khẩu sudo để Ansible có quyền cài gói và ghi cấu hình hệ thống.

Sau đó tạo `~/.config/infra/telegram.env`, đặt quyền `600` và cài lịch Playwright:

```bash
chmod 600 ~/.config/infra/telegram.env
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-monitor.yml -K
sudo /usr/local/bin/run-phone-shop-e2e --notification-test
```

Cuối cùng đăng ký GitHub self-hosted runner bằng token đăng ký dùng một lần, rồi chạy `phone-shop-cicd.yml`. Không ghi token vào Git và xóa file tạm chứa token ngay sau khi đăng ký. Runner hiện tại đã đăng ký xong nên không cần làm lại bước này trên VM cũ.

Mỗi VM mới sẽ có database trống và bộ bí mật riêng. Ansible cài cùng cấu hình và dịch vụ; Ansible không tự sao chép dữ liệu MySQL của VM cũ. Muốn giữ dữ liệu, phải khôi phục file backup vào VM mới.

## 10. Snapshot VMware và khôi phục

Snapshot hiện có tên `phone-shop-infra-complete-2026-10-23`. Snapshot lưu trạng thái VM tại một thời điểm để quay lại khi thử nghiệm làm hỏng máy.

Trên Windows có thể xem danh sách snapshot:

```powershell
& 'C:\Program Files\VMware\VMware Workstation\vmrun.exe' -T ws listSnapshots 'D:\Infra\Machine_automation.vmx'
```

- `&`: yêu cầu PowerShell chạy file chương trình ở đường dẫn có dấu cách.
- `vmrun.exe`: công cụ dòng lệnh đi kèm VMware Workstation.
- `-T ws`: chọn VMware Workstation.
- `listSnapshots`: chỉ liệt kê snapshot, không thay đổi VM.

Snapshot không thay thế backup database. Snapshot nằm cùng máy Windows; nếu ổ đĩa hỏng thì cả VM và snapshot có thể mất. File backup quan trọng nên được sao chép thêm sang nơi khác.

## 11. Khi pipeline hoặc ứng dụng bị lỗi

### Deploy đứng ở Queued

Nguyên nhân thường gặp:

- VM đang tắt.
- VM mất Internet.
- Runner không chạy.
- Nhãn runner không khớp.

Kiểm tra:

```bash
systemctl is-active actions.runner.thoa2005-Phone-shop.phone-shop-vm.service
sudo journalctl -u actions.runner.thoa2005-Phone-shop.phone-shop-vm.service -n 50 --no-pager
```

Khởi động lại runner:

```bash
sudo systemctl restart actions.runner.thoa2005-Phone-shop.phone-shop-vm.service
```

### Build Spring Boot bị đỏ

Mở job `Build Spring Boot` trên GitHub và tìm dòng đầu tiên chứa `[ERROR]`.

Chạy lại trên VM để tái hiện:

```bash
cd ~/Phone-shop/phoneshop-backend
mvn clean verify
```

### Build Next.js bị đỏ

```bash
cd ~/Phone-shop/phoneshop-frontend
npm ci --no-audit --no-fund
NEXT_PUBLIC_API_URL=/api NEXT_PUBLIC_UPLOAD_URL=/uploads npm run build
```

### Nginx trả về 502

`502 Bad Gateway` thường có nghĩa Nginx còn chạy nhưng backend hoặc frontend phía sau không hoạt động.

```bash
systemctl status phone-shop-backend phone-shop-frontend nginx --no-pager
curl -I http://127.0.0.1:3000/
curl -sS -o /dev/null -w 'backend=%{http_code}\n' http://127.0.0.1:8081/api/products
```

### IP VM thay đổi

```bash
ip -4 addr show ens33
```

Tìm dòng `inet`. Nếu IP không còn là `192.168.100.4`, dùng IP mới để SSH và mở web. GitHub runner vẫn hoạt động vì nó kết nối từ VM ra GitHub.

## 12. Hoàn tác một lần triển khai lỗi

Không dùng `git reset --hard` trên nhánh chung. Tạo một commit đảo thay đổi rồi push:

```bash
git log --oneline -5
git revert <commit-bi-loi>
git push origin main
```

`git revert` tạo commit mới để đảo nội dung commit lỗi. CI/CD sẽ kiểm tra và tự triển khai commit hoàn tác.

## 13. Bảo mật

- Không commit token GitHub, khóa SSH, mật khẩu MySQL hoặc token Telegram.
- Token đăng ký runner chỉ dùng một lần và file tạm đã bị xóa sau khi đăng ký.
- Runner chỉ được dùng cho job Deploy khi push vào `main`; pull request không chạy trên VM.
- File sudoers chỉ cho tài khoản `vanthoa` gọi `/usr/local/sbin/deploy-phone-shop` không cần nhập mật khẩu.
- Script deploy kiểm tra commit phải là SHA 40 ký tự và dùng khóa `flock` để tránh hai lần deploy chạy cùng lúc.
- Vì repo Phone Shop là public, chỉ người tin cậy mới nên có quyền push hoặc sửa workflow trên nhánh `main`.

## 14. Phần chưa tự động hóa hoặc chưa phù hợp production

- Việc tạo VM VMware mới vẫn làm thủ công.
- IP `192.168.100.4` là IP DHCP trong LAN, chưa phải IP tĩnh và chưa phải địa chỉ Internet công khai.
- Chưa có domain và chứng chỉ HTTPS thật.
- Backup vẫn nằm trong chính VM, chưa sao chép sang máy/ổ lưu trữ khác.
- Chưa có hệ thống giám sát tập trung về CPU, RAM, dung lượng đĩa và cảnh báo dịch vụ ngoài Telegram của Playwright.
- Inventory Ansible hiện chỉ cấu hình `localhost`; chưa có mô hình một máy điều khiển quản lý nhiều server qua SSH.
- Snapshot và tạo VM chưa được nối vào pipeline CI/CD.

Như vậy, hệ thống hiện là một lab tự động hóa khá đầy đủ cho một VM. Nó chưa phải kiến trúc production có khả năng chịu lỗi hoặc mở rộng nhiều máy.

## 15. Các thuật ngữ

- **CI**: tự build và kiểm tra mã nguồn sau khi push hoặc tạo pull request.
- **CD**: tự đưa phiên bản đã qua CI lên máy chạy ứng dụng.
- **Workflow**: file YAML mô tả các job GitHub Actions.
- **Job**: một nhóm bước như build backend, build frontend hoặc deploy.
- **Runner**: máy thực thi job GitHub Actions.
- **Self-hosted runner**: runner do mình quản lý; trong dự án này nó nằm trong VM Ubuntu.
- **Commit SHA**: mã định danh duy nhất của một commit Git.
- **Idempotent**: chạy Ansible nhiều lần vẫn đưa hệ thống về cùng trạng thái mong muốn.
- **Reverse proxy**: Nginx nhận truy cập ở cổng 80 rồi chuyển yêu cầu tới Next.js hoặc Spring Boot.

## 16. Checklist xác nhận toàn bộ hệ thống tốt

- [ ] GitHub Actions có ba job màu xanh.
- [ ] Runner là `active` và `enabled`.
- [ ] Backend, frontend, Nginx và MySQL đều `active`.
- [ ] Web trả HTTP 200.
- [ ] API trả HTTP 200.
- [ ] Commit trên VM trùng commit được deploy trên GitHub.
- [ ] Timer backup có lần chạy tiếp theo.
- [ ] Timer Playwright có lần chạy tiếp theo.
- [ ] File backup MySQL gần nhất tồn tại.
- [ ] Telegram nhận được kết quả lần chạy Playwright gần nhất.
- [ ] UFW đang bật và chỉ mở các cổng dự kiến.
- [ ] Cổng 3000, 8081 và 3306 chỉ lắng nghe trên loopback.
- [ ] Dung lượng đĩa còn đủ: `df -h`.
- [ ] Repo Phone Shop và repo hạ tầng không có thay đổi ngoài ý muốn: `git status -sb`.
