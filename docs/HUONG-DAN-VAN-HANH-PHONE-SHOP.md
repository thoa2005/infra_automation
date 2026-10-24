# Hướng dẫn đầy đủ về hạ tầng và vận hành Phone Shop

Tài liệu này mô tả toàn bộ những gì đã cấu hình trên VM Ubuntu cho Phone Shop, cách các thành phần nối với nhau, cách kiểm tra từng phần và cách dựng lại cấu hình bằng Ansible.

CI/CD chỉ là một phần của hệ thống. VM hiện còn đảm nhiệm web, API, database, reverse proxy, kiểm thử trình duyệt, gửi Telegram, firewall, log và backup.

Cách đọc tài liệu:

- Muốn biết máy chủ hiện có gì: đọc mục 1 đến mục 3.
- Muốn xem lại chính xác quá trình đã làm từ đầu: đọc mục 4.
- Muốn kiểm tra từng thành phần và hiểu kết quả: đọc mục 5.
- Muốn kiểm tra nhanh hằng ngày: đọc mục 7.
- Muốn dựng lại trên VM mới: đọc mục 11.
- Muốn xử lý lỗi: đọc mục 13.

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

## 4. Quy trình chi tiết đã thực hiện từ máy ảo trống đến hệ thống hiện tại

Đây là phần ghi lại quy trình đã làm theo thứ tự thời gian. Các lệnh Bash chạy trong Ubuntu, còn khối `powershell` chạy trên Windows.

### Giai đoạn 1: Chuẩn bị VM Ubuntu, Bridged network và SSH

#### Bước 1.1: Tạo và nối mạng cho VM

VM được tạo thủ công trong VMware Workstation. Trong phần Network Adapter đã chọn:

1. `Connected`.
2. `Connect at power on`.
3. `Bridged: Connected directly to the physical network`.

Bridged làm cho VM giống một máy riêng trong LAN. Router cấp địa chỉ cho card `ens33`; vì vậy Windows có thể kết nối thẳng tới VM.

Trong Ubuntu đã kiểm tra cấu hình Netplan:

```bash
sudo netplan get
```

Cấu hình quan trọng là `ens33`, MAC address đúng với VMware, `dhcp4: true` và `set-name: ens33`. `dhcp4: true` yêu cầu DHCP cấp IPv4; nó không đảm bảo địa chỉ luôn là `192.168.100.4`.

Sau đó làm mới DHCP và kiểm tra IP:

```bash
sudo networkctl renew ens33
ip -4 addr show ens33
```

- `networkctl renew ens33`: yêu cầu cấp lại lease DHCP cho card.
- `ip -4 addr show ens33`: xem IPv4 được cấp.

#### Bước 1.2: Cài công cụ nền

```bash
sudo apt update
sudo apt install openssh-server git tmux ansible-core
sudo systemctl enable --now ssh
```

- `apt update`: tải danh sách phiên bản gói mới từ repository Ubuntu.
- `apt install`: cài SSH server, Git, tmux và Ansible.
- `systemctl enable --now ssh`: vừa bật SSH ngay, vừa cho SSH tự bật khi VM khởi động.

Lưu ý cú pháp đúng của tùy chọn bỏ gói đề xuất là:

```bash
sudo apt install --no-install-recommends ansible-core
```

Tùy chọn phải nằm trọn trên cùng câu lệnh; lần trước chữ `ansible-core` bị xuống dòng giữa chừng nên APT hiểu sai.

#### Bước 1.3: Thiết lập SSH key

Public key từ Windows được thêm vào file `~/.ssh/authorized_keys` của `vanthoa`. Không sao chép private key vào VM và không đưa private key vào Git.

Quyền file cần đúng:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

Sau đó kiểm tra từ Windows:

```powershell
ssh vanthoa@192.168.100.4
```

Khi vào được dấu nhắc `vanthoa@websever:~$`, kết nối SSH đã hoàn thành.

#### Bước 1.4: Tạo phiên tmux cùng theo dõi

```bash
tmux new-session -s cowork
```

- `new-session`: tạo phiên terminal mới.
- `-s cowork`: đặt tên phiên là `cowork`.

Terminal khác theo dõi cùng phiên bằng:

```bash
tmux attach -t cowork
```

tmux chỉ giúp quan sát và giữ terminal. Nó không tự cài hoặc triển khai ứng dụng.

### Giai đoạn 2: Khởi tạo repo hạ tầng và inventory Ansible

Repo hạ tầng được đặt tại `/home/vanthoa/infra_automation` trong VM và `D:\Infra\infra_automation` trên Windows.

Nếu dựng lại máy, clone bằng:

```bash
cd ~
git clone git@github.com:thoa2005/infra_automation.git
cd ~/infra_automation
```

Inventory được tạo tại `ansible/inventory/hosts.ini`:

```ini
[webservers]
localhost ansible_connection=local ansible_become_exe=/usr/bin/sudo.ws
```

Giải thích:

- `[webservers]`: tên nhóm máy mà playbook dùng ở `hosts: webservers`.
- `localhost`: máy đích chính là VM hiện tại.
- `ansible_connection=local`: Ansible chạy task trực tiếp, không SSH vòng lại chính nó.
- `ansible_become_exe=/usr/bin/sudo.ws`: Ubuntu lab dùng `sudo-rs`; đường dẫn này giúp Ansible nhận đúng chương trình sudo tương thích.

Kiểm tra inventory:

```bash
ansible-inventory -i ansible/inventory/hosts.ini --graph
ansible -i ansible/inventory/hosts.ini webservers -m ping
```

Lệnh thứ nhất phải hiển thị `webservers -> localhost`; lệnh thứ hai cần trả `SUCCESS` và `pong`.

### Giai đoạn 3: Tự động cài Nginx đầu tiên

Ban đầu đã tạo ba file:

- `ansible/playbooks/nginx.yml`: playbook cài và bật Nginx.
- `ansible/files/index.html`: trang HTML thử nghiệm.
- `ansible/files/check-nginx.sh`: script kiểm tra HTTP.

Luồng của `nginx.yml` là:

1. Cài gói `nginx` bằng APT.
2. Bật và khởi động service Nginx.
3. Sao chép trang thử vào `/var/www/html/index.html`.
4. Cài script kiểm tra `/usr/local/bin/check-nginx`.
5. Tạo cron chạy kiểm tra mỗi 5 phút.

Trước tiên kiểm tra YAML:

```bash
cd ~/infra_automation
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/nginx.yml --syntax-check
```

Nếu chỉ thấy `playbook: ansible/playbooks/nginx.yml` mà không có lỗi thì cú pháp đúng.

Chạy cấu hình thật:

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/nginx.yml -K
```

`-K` hỏi mật khẩu sudo vì cài gói và ghi vào thư mục hệ thống cần quyền quản trị. Kết quả `failed=0` chứng minh playbook chạy xong.

Kiểm tra Nginx ban đầu:

```bash
systemctl is-active nginx
curl -I http://127.0.0.1/
sudo /usr/local/bin/check-nginx
```

Nginx cần `active`, curl cần `HTTP/1.1 200 OK` và script cần báo kiểm tra thành công.

### Giai đoạn 4: Cài môi trường Spring Boot, Next.js, MySQL và Playwright

File `ansible/playbooks/phone-shop-prereqs.yml` được viết để thay thế việc cài từng gói bằng tay. Playbook thực hiện:

1. Cài `openjdk-17-jdk`, `maven`, `nodejs`, `npm`, `mysql-server`, `python3-pymysql`, `git`, `curl`.
2. Bật MySQL và cho tự khởi động.
3. Tạo `/opt/phone-shop-tests`.
4. Sao chép bộ test mẫu và `package-lock.json`.
5. Chạy `npm ci`.
6. Xác định Chromium của Playwright.
7. Cài thư viện hệ thống và Chromium nếu chưa có.

Chạy playbook:

```bash
cd ~/infra_automation
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-prereqs.yml -K
```

Tại sao dùng `npm ci` thay cho `npm install`: `npm ci` cài đúng phiên bản trong `package-lock.json`, giúp máy mới có cùng dependency với máy cũ.

Kiểm tra sau khi cài:

```bash
java -version
mvn -version
node --version
npm --version
mysql --version
cd /opt/phone-shop-tests
npx playwright --version
```

Nếu tất cả lệnh in phiên bản thì môi trường nền đã sẵn sàng.

### Giai đoạn 5: Lấy mã nguồn Phone Shop và triển khai ứng dụng

#### Bước 5.1: Cho VM đọc repo GitHub

VM cần SSH key có quyền đọc repo `git@github.com:thoa2005/Phone-shop.git`. Kiểm tra kết nối GitHub:

```bash
ssh -T git@github.com
```

GitHub thường trả thông báo xác thực thành công nhưng không cung cấp shell. Điều đó là bình thường.

#### Bước 5.2: Cài collection Ansible

File `ansible/requirements.yml` khai báo:

```yaml
collections:
  - name: ansible.mysql
    version: ">=5.2.0"
  - name: community.general
    version: ">=11.0.0"
```

Cài bằng:

```bash
cd ~/infra_automation
ansible-galaxy collection install -r ansible/requirements.yml
```

`ansible.mysql` cung cấp module tạo database/user MySQL; `community.general` cung cấp module múi giờ và UFW.

#### Bước 5.3: Chạy playbook triển khai

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-deploy.yml -K
```

Playbook `phone-shop-deploy.yml` làm lần lượt:

1. Bảo đảm Git, Nginx, Java, Maven, Node.js, npm, MySQL và PyMySQL đã cài.
2. Bật MySQL và Nginx.
3. Tạo `~/.config/infra` với quyền `0700`.
4. Sinh mật khẩu database 32 ký tự và JWT secret 64 ký tự; chạy lại vẫn đọc lại giá trị cũ.
5. Tạo database `phoneshop_db` mã hóa `utf8mb4`.
6. Tạo user MySQL `phoneshop@localhost` bằng plugin `caching_sha2_password`.
7. Sinh `/etc/phone-shop/backend.env` quyền `0600`.
8. Sinh `~/.config/infra/e2e.env` cho Playwright.
9. Clone hoặc cập nhật mã nguồn vào `~/Phone-shop`.
10. Chạy `mvn clean package -DskipTests` để tạo backend JAR.
11. Chạy `npm ci` và `npm run build` để tạo bản Next.js production.
12. Tạo thư mục uploads.
13. Tạo hai systemd service backend/frontend.
14. Cài cấu hình reverse proxy Nginx.
15. Khởi động lại ứng dụng và đợi từng cổng trả HTTP 200.

Vì sao lúc deploy dùng `-DskipTests`: CI đã chạy `mvn verify` trước khi CD; bước deploy chỉ cần build artifact nhanh. Khi chạy playbook thủ công mà chưa qua CI, nên tự chạy `mvn verify` trước.

#### Bước 5.4: File môi trường backend được sinh

Template `phone-shop-backend.env.j2` tạo các biến:

```text
DB_URL=jdbc:mysql://localhost:3306/phoneshop_db...
DB_USERNAME=phoneshop
DB_PASSWORD=<giá trị được sinh>
JWT_SECRET=<giá trị được sinh>
```

Không ghi giá trị thật vào tài liệu hoặc Git. Chỉ root được đọc file kết quả:

```bash
sudo stat -c '%a %U:%G %n' /etc/phone-shop/backend.env
```

Kết quả đúng là quyền `600` và chủ sở hữu `root:root`.

#### Bước 5.5: Cấu hình Nginx production

Template Nginx định tuyến:

```text
/          -> http://127.0.0.1:3000
/api/      -> http://127.0.0.1:8081
/uploads/  -> http://127.0.0.1:8081
```

Kiểm tra toàn bộ ứng dụng:

```bash
systemctl is-active phone-shop-backend phone-shop-frontend nginx mysql
curl -sS -o /dev/null -w 'web=%{http_code}\n' http://127.0.0.1/
curl -sS -o /dev/null -w 'api=%{http_code}\n' http://127.0.0.1/api/products
```

Mong đợi bốn dòng `active`, `web=200` và `api=200`.

### Giai đoạn 6: Đưa bộ test Playwright vào dự án và gửi Telegram

Bộ test Playwright được đặt trong repo Phone Shop tại `tests/e2e/`. `package.json` ở thư mục gốc có script:

```json
"test:e2e": "playwright test"
```

Cài dependency và trình duyệt:

```bash
cd ~/Phone-shop
npm ci --no-audit --no-fund
npx playwright install chromium
```

- `--no-audit`: không chạy báo cáo audit trong lúc cài.
- `--no-fund`: không in thông báo tài trợ.
- `playwright install chromium`: tải đúng Chromium tương thích với Playwright.

#### Bước 6.1: Tạo file Telegram ngoài Git

```bash
mkdir -p ~/.config/infra
chmod 700 ~/.config/infra
nano ~/.config/infra/telegram.env
```

Nội dung được nhập bằng token/chat ID thật, không dùng dấu `< >`:

```text
TELEGRAM_TOKEN=token-cua-bot
TELEGRAM_CHAT_ID=id-cuoc-tro-chuyen
```

Sau khi lưu:

```bash
chmod 600 ~/.config/infra/telegram.env
```

Quyền `600` nghĩa chỉ user sở hữu được đọc và ghi.

#### Bước 6.2: Cài service và timer kiểm thử

```bash
cd ~/infra_automation
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-monitor.yml -K
```

Playbook sao chép script vào `/usr/local/bin/run-phone-shop-e2e`, tạo service `phone-shop-e2e.service`, timer `phone-shop-e2e.timer` và bật lịch 07:00 hằng ngày.

Thử riêng kết nối Telegram:

```bash
sudo /usr/local/bin/run-phone-shop-e2e --notification-test
```

Chạy test ngay mà không đợi đến 07:00:

```bash
sudo systemctl start --no-block phone-shop-e2e.service
sudo journalctl -fu phone-shop-e2e.service
```

- `systemctl start --no-block`: yêu cầu systemd bắt đầu test rồi trả terminal ngay để có thể xem log.
- `journalctl -f`: theo dõi log mới liên tục; nhấn `Ctrl+C` chỉ dừng xem log, không dừng test.

### Giai đoạn 7: Firewall, giới hạn log và backup database

Chạy playbook vận hành:

```bash
cd ~/infra_automation
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-operations.yml -K
```

Playbook làm theo thứ tự:

1. Đặt timezone `Asia/Ho_Chi_Minh`.
2. Cài UFW và gzip.
3. Mở SSH trước để tránh tự khóa kết nối.
4. Mở Nginx Full cho HTTP/HTTPS.
5. Đặt incoming mặc định `deny`, outgoing mặc định `allow`.
6. Bật UFW.
7. Giới hạn journal tối đa 500 MB và 14 ngày.
8. Tạo file đăng nhập MySQL dành riêng cho backup.
9. Tạo thư mục `/var/backups/phone-shop` quyền `0700`.
10. Cài script, service và timer backup lúc 02:00.
11. Chạy một bản backup thử ngay.
12. Xác nhận có file `.sql.gz` và dùng `gzip -t` kiểm tra file nén.

Kiểm tra:

```bash
timedatectl
sudo ufw status verbose
systemctl list-timers phone-shop-backup.timer --all
sudo ls -lh /var/backups/phone-shop/
sudo journalctl -u phone-shop-backup.service -n 50 --no-pager
```

### Giai đoạn 8: Tạo CI/CD GitHub Actions

#### Bước 8.1: Tạo workflow trong repo Phone Shop

File `.github/workflows/ci-cd.yml` được thêm vào repo ứng dụng. Workflow có ba job:

1. `Build Spring Boot` chạy `mvn verify` trên runner Ubuntu của GitHub.
2. `Build Next.js` chạy `npm ci` và `npm run build` trên runner Ubuntu của GitHub.
3. `Deploy production VM` chỉ chạy khi push vào `main` và hai job build đã thành công.

Job deploy chọn runner bằng bốn nhãn:

```yaml
runs-on:
  - self-hosted
  - linux
  - x64
  - phone-shop
```

Nó gọi:

```bash
sudo -n /usr/local/sbin/deploy-phone-shop "${GITHUB_SHA}"
```

`GITHUB_SHA` là commit chính xác đã được CI build. `sudo -n` không hỏi mật khẩu; sudoers chỉ cho phép gọi đúng script deploy.

#### Bước 8.2: Cài self-hosted runner trên VM

GitHub tạo registration token dùng một lần tại Settings → Actions → Runners. Token được truyền cho playbook, không commit.

Một cách tránh lưu token trong history:

```bash
cd ~/infra_automation
umask 077
read -rsp 'GitHub runner token: ' RUNNER_TOKEN
printf '\ngithub_runner_token: "%s"\n' "$RUNNER_TOKEN" > /tmp/runner-vars.yml
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-cicd.yml -K -e @/tmp/runner-vars.yml
shred -u /tmp/runner-vars.yml
unset RUNNER_TOKEN
```

Giải thích:

- `umask 077`: file mới chỉ cho chủ sở hữu truy cập.
- `read -s`: nhập token nhưng không hiện trên màn hình.
- `-e @file`: Ansible đọc biến bổ sung từ file.
- `shred -u`: ghi đè rồi xóa file token.
- `unset`: xóa biến khỏi shell hiện tại.

Playbook tải GitHub runner, kiểm tra SHA256, giải nén vào `~/actions-runner`, đăng ký nhãn `phone-shop`, cài runner thành systemd service, rồi tạo sudoers chỉ cho script deploy.

#### Bước 8.3: Script deploy hoạt động ra sao

`/usr/local/sbin/deploy-phone-shop` thực hiện:

1. Chỉ nhận đúng một SHA Git 40 ký tự.
2. Dùng `flock` để từ chối nếu một lần deploy khác đang chạy.
3. Pull repo hạ tầng bằng `--ff-only`.
4. Nạp collection Ansible từ thư mục của `vanthoa`.
5. Chạy `phone-shop-deploy.yml` với `phone_shop_version=<SHA>`.
6. Curl web và API; nếu không phải HTTP thành công thì job thất bại.

Biến sau đã được thêm vì deploy chạy dưới root nhưng collection được cài cho user `vanthoa`:

```bash
export ANSIBLE_COLLECTIONS_PATH="/home/vanthoa/.ansible/collections:/usr/share/ansible/collections"
```

Đây là cách đã sửa lỗi CI đầu tiên không tìm thấy collection MySQL.

#### Bước 8.4: Kích hoạt pipeline

Trong repo Phone Shop trên Windows:

```powershell
cd D:\Infra\Phone-shop
git add .github/workflows/ci-cd.yml
git commit -m "Add Phone Shop CI CD workflow"
git push origin main
```

`git push` kích hoạt workflow. Lần chạy thành công đầu tiên là:

<https://github.com/thoa2005/Phone-shop/actions/runs/39987402072>

### Giai đoạn 9: Chụp snapshot hoàn tất

Sau khi web, API, database, timer, firewall, backup và CI/CD hoạt động, snapshot `phone-shop-infra-complete-2026-10-23` được tạo trong VMware Workstation.

Kiểm tra danh sách từ Windows:

```powershell
& 'C:\Program Files\VMware\VMware Workstation\vmrun.exe' -T ws listSnapshots 'D:\Infra\Machine_automation.vmx'
```

Snapshot là điểm quay lại của VM, còn backup `.sql.gz` bảo vệ dữ liệu MySQL. Hai loại này có mục đích khác nhau.

### Những lỗi đã gặp và cách đã xử lý

1. **`ens33` không có IPv4:** kiểm tra Bridged/Connected, Netplan và renew DHCP.
2. **APT báo tùy chọn `--no-install-recommends` sai:** lệnh bị xuống dòng giữa `ansible-core`; đã chạy lại nguyên câu.
3. **Ansible không match `webservers`:** sửa header inventory thành `[webservers]` để trùng `hosts: webservers`.
4. **MySQL báo `mysql_native_password is not loaded`:** Ubuntu/MySQL mới không nạp plugin cũ; chuyển user ứng dụng sang `caching_sha2_password`.
5. **CI deploy không tìm thấy module `ansible.mysql`:** thêm `ANSIBLE_COLLECTIONS_PATH` vào script deploy.
6. **Nginx trả 502 ngay sau khi bật VM:** backend/frontend vẫn đang khởi tạo; chờ health check trả 200. Spring Boot mất khoảng 23 giây và Next.js khoảng 18 giây trong lần kiểm tra ngày 24/10/2026.
7. **Playwright báo service failed:** timer và script vẫn hoạt động; lần gần nhất có 36 test đạt, 8 lỗi, 1 chập chờn nên service trả exit code 1 để báo đúng trạng thái kiểm thử.

## 5. Máy chủ đã được xây dựng như thế nào và kiểm tra ra sao

Phần này đi theo từng chức năng. Mỗi mục đều nêu trạng thái đã làm, cách triển khai, lệnh kiểm tra và cách đọc kết quả.

### 5.1. Máy ảo và kết nối mạng

**Đã làm được gì**

- Ubuntu chạy trong VMware Workstation.
- Card `ens33` dùng chế độ Bridged nên VM có một IP riêng trong mạng LAN.
- Windows có thể SSH và mở website trong VM.
- IP hiện tại là `192.168.100.4/24`, được cấp bằng DHCP.

**Đã làm như thế nào**

Card mạng của VM được chọn `Bridged: Connected directly to the physical network`, đồng thời bật `Connected` và `Connect at power on`. Netplan trong Ubuntu đặt `dhcp4: true`, nên router cấp IPv4 cho `ens33`.

**Kiểm tra**

```bash
ip -4 -brief addr show ens33
ip route
```

- `ip -4`: chỉ xem IPv4.
- `-brief`: hiển thị ngắn gọn.
- `addr show ens33`: chỉ xem card `ens33`.
- `ip route`: xem đường đi mạng; dòng bắt đầu bằng `default via` cho biết gateway.

Kết quả đúng phải có `ens33 UP` và một địa chỉ dạng `192.168.100.x/24`. Nếu IP thay đổi, dùng IP mới để SSH và mở web.

Từ Windows kiểm tra kết nối:

```powershell
Test-NetConnection 192.168.100.4 -Port 22
Test-NetConnection 192.168.100.4 -Port 80
```

`TcpTestSucceeded : True` nghĩa là Windows kết nối được tới SSH hoặc website.

### 5.2. SSH và phiên terminal tmux

**Đã làm được gì**

- Windows đăng nhập Ubuntu bằng SSH key mà không cần đưa mật khẩu vào câu lệnh.
- Phiên tmux `cowork` được dùng để bạn có thể nhìn các lệnh chạy trong cùng terminal.

**Đã làm như thế nào**

Public key của Windows được thêm vào `~/.ssh/authorized_keys` của user `vanthoa`. tmux chạy bên trong Ubuntu; nhiều terminal có thể cùng attach vào một session.

**Kiểm tra**

```powershell
ssh vanthoa@192.168.100.4
```

Sau khi vào Ubuntu:

```bash
tmux ls
tmux attach -t cowork
```

- `tmux ls`: liệt kê session.
- `attach`: nối terminal hiện tại vào session.
- `-t cowork`: chọn session có tên `cowork`.

Nhấn `Ctrl+B`, thả ra rồi nhấn `D` để rời tmux nhưng vẫn giữ tiến trình chạy.

### 5.3. Ansible tự động cấu hình máy

**Đã làm được gì**

Ansible có thể cài gói, tạo database, sinh file cấu hình, build ứng dụng, cài service, cấu hình Nginx, firewall, backup, kiểm thử và runner. Chạy lại playbook sẽ đưa máy về cùng trạng thái mong muốn.

**Đã làm như thế nào**

Inventory `ansible/inventory/hosts.ini` khai báo nhóm `webservers` với `localhost`. Các playbook YAML dùng module Ansible để thay cho việc gõ từng lệnh cài đặt thủ công.

**Kiểm tra cú pháp mà chưa thay đổi máy**

```bash
cd ~/infra_automation
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-deploy.yml --syntax-check
```

- `-i`: chọn inventory.
- `--syntax-check`: chỉ kiểm tra cấu trúc YAML và module, chưa chạy task.

**Chạy thật**

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-deploy.yml -K
```

`-K` yêu cầu Ansible hỏi mật khẩu sudo. Cuối kết quả cần có `failed=0` và `unreachable=0`. `changed` lớn hơn 0 nghĩa là Ansible vừa điều chỉnh máy; `changed=0` nghĩa là cấu hình đã đúng từ trước.

### 5.4. Java, Node.js và môi trường chạy ứng dụng

**Đã làm được gì**

- Java 17 và Maven build/chạy Spring Boot.
- Node.js 22 và npm build/chạy Next.js và Playwright.
- Git và curl phục vụ lấy mã nguồn và kiểm tra HTTP.

**Đã làm như thế nào**

Playbook `phone-shop-prereqs.yml` và `phone-shop-deploy.yml` dùng module `apt` cài các gói. Frontend được cài dependency bằng `npm ci`; backend được build bằng Maven.

**Kiểm tra**

```bash
java -version
mvn -version
node --version
npm --version
git --version
curl --version | head -n 1
```

Nếu một lệnh báo `command not found`, gói tương ứng chưa được cài hoặc không nằm trong `PATH`.

### 5.5. MySQL và dữ liệu Phone Shop

**Đã làm được gì**

- MySQL tự chạy cùng VM.
- Database `phoneshop_db` đã được tạo với mã hóa `utf8mb4`.
- Ứng dụng có tài khoản MySQL riêng tên `phoneshop`.
- Mật khẩu database được sinh và lưu ngoài Git.

**Đã làm như thế nào**

`phone-shop-deploy.yml` dùng `ansible.mysql.mysql_db` và `ansible.mysql.mysql_user`. Mật khẩu được tạo trong `~/.config/infra/phoneshop-db-password`; biến môi trường backend nằm tại `/etc/phone-shop/backend.env` với quyền `0600`.

**Kiểm tra an toàn, không in mật khẩu**

```bash
systemctl is-active mysql
systemctl is-enabled mysql
sudo mysql -N -e "SHOW DATABASES LIKE 'phoneshop_db';"
sudo mysql -N -e "SELECT user,host FROM mysql.user WHERE user='phoneshop';"
```

- `is-active` cần trả `active`.
- `is-enabled` cần trả `enabled`.
- `-N` bỏ tiêu đề cột để kết quả dễ đọc.
- Hai lệnh SQL chỉ kiểm tra tên database và tài khoản, không làm thay đổi dữ liệu.

### 5.6. Spring Boot backend

**Đã làm được gì**

Backend được build thành file JAR, chạy bằng service `phone-shop-backend` và chỉ nghe trên loopback ở cổng `8081`.

**Đã làm như thế nào**

Ansible chạy `mvn clean package -DskipTests`, tạo `/etc/systemd/system/phone-shop-backend.service`, đọc biến bí mật từ `/etc/phone-shop/backend.env` và bật service tự khởi động.

**Kiểm tra**

```bash
systemctl is-active phone-shop-backend
systemctl is-enabled phone-shop-backend
curl -sS -o /dev/null -w 'backend=%{http_code}\n' http://127.0.0.1:8081/api/products
```

Hai lệnh systemd cần trả `active` và `enabled`; curl cần in `backend=200`.

### 5.7. Next.js frontend

**Đã làm được gì**

Frontend được build production, chạy bằng service `phone-shop-frontend` và chỉ nghe trên loopback ở cổng `3000`.

**Đã làm như thế nào**

Ansible chạy `npm ci` rồi `npm run build` với API URL là `/api`, tạo service systemd và chạy `npm start -- --hostname 127.0.0.1 --port 3000`.

**Kiểm tra**

```bash
systemctl is-active phone-shop-frontend
systemctl is-enabled phone-shop-frontend
curl -sS -o /dev/null -w 'frontend=%{http_code}\n' http://127.0.0.1:3000/
```

Kết quả mong đợi là `active`, `enabled` và `frontend=200`.

### 5.8. Nginx reverse proxy

**Đã làm được gì**

Người dùng chỉ cần truy cập cổng 80. Nginx chuyển `/` tới Next.js, còn `/api` và `/uploads` tới Spring Boot. Cổng nội bộ 3000 và 8081 không cần mở ra mạng LAN.

**Đã làm như thế nào**

Template `phone-shop-nginx.conf.j2` được cài vào `/etc/nginx/sites-available/phone-shop`, tạo symlink trong `sites-enabled` và tắt site mặc định.

**Kiểm tra**

```bash
sudo nginx -t
systemctl is-active nginx
curl -sS -o /dev/null -w 'web=%{http_code}\n' http://127.0.0.1/
curl -sS -o /dev/null -w 'api=%{http_code}\n' http://127.0.0.1/api/products
```

- `nginx -t` cần báo `syntax is ok` và `test is successful`.
- Nginx cần `active`.
- Web và API cần trả `200`.

### 5.9. systemd và tự khởi động cùng VM

**Đã làm được gì**

Backend, frontend, Nginx, MySQL và GitHub runner đều được bật tự khởi động. Nếu tiến trình backend hoặc frontend lỗi, systemd thử chạy lại sau 5 giây.

**Đã làm như thế nào**

Ansible tạo unit file trong `/etc/systemd/system/`, gọi `daemon-reload`, rồi đặt `enabled: true` và `state: restarted` hoặc `started`.

**Kiểm tra một lần cho tất cả dịch vụ**

```bash
systemctl is-active phone-shop-backend phone-shop-frontend nginx mysql actions.runner.thoa2005-Phone-shop.phone-shop-vm.service
systemctl is-enabled phone-shop-backend phone-shop-frontend nginx mysql actions.runner.thoa2005-Phone-shop.phone-shop-vm.service
```

Mỗi lệnh phải in năm dòng. Tất cả dòng của lệnh đầu cần là `active`; tất cả dòng của lệnh sau cần là `enabled`.

### 5.10. Firewall UFW và bảo vệ cổng

**Đã làm được gì**

Kết nối vào mặc định bị chặn. Chỉ OpenSSH và Nginx Full được cho phép, tương ứng cổng 22, 80 và 443. MySQL, backend và frontend không được mở trực tiếp ra LAN.

**Đã làm như thế nào**

`phone-shop-operations.yml` dùng module `community.general.ufw`: cho phép SSH trước, cho phép Nginx, đặt incoming deny, outgoing allow rồi bật UFW.

**Kiểm tra**

```bash
sudo ufw status verbose
ss -ltn | grep -E ':(22|80|443|3000|3306|8081)[[:space:]]'
```

Trong kết quả UFW phải có `Status: active`, `Default: deny (incoming)` và các rule OpenSSH/Nginx. Các cổng 3000, 3306 và 8081 phải gắn với địa chỉ loopback, không phải `0.0.0.0`.

### 5.11. Log hệ thống

**Đã làm được gì**

Log của service được lưu bằng systemd journal. Dung lượng journal được giới hạn 500 MB, log runtime 100 MB và thời gian giữ tối đa 14 ngày.

**Đã làm như thế nào**

Ansible tạo `/etc/systemd/journald.conf.d/phone-shop-limits.conf` và khởi động lại `systemd-journald`.

**Kiểm tra**

```bash
sudo cat /etc/systemd/journald.conf.d/phone-shop-limits.conf
sudo journalctl --disk-usage
sudo journalctl -u phone-shop-backend -n 30 --no-pager
```

- `--disk-usage`: xem journal đang chiếm bao nhiêu dung lượng.
- `-u`: lọc theo service.
- `-n 30`: lấy 30 dòng cuối.
- `--no-pager`: in thẳng ra terminal.

### 5.12. Backup MySQL tự động

**Đã làm được gì**

Database được dump và nén lúc 02:00 hằng ngày. Backup nằm trong `/var/backups/phone-shop/` và file quá 14 ngày được xóa.

**Đã làm như thế nào**

Ansible cài `/usr/local/sbin/backup-phone-shop`, tạo `phone-shop-backup.service` cùng `phone-shop-backup.timer`. Thông tin đăng nhập backup nằm trong `/etc/phone-shop/backup.cnf` với quyền `0600`.

**Kiểm tra**

```bash
systemctl is-enabled phone-shop-backup.timer
systemctl list-timers phone-shop-backup.timer --all
sudo ls -lh /var/backups/phone-shop/
sudo journalctl -u phone-shop-backup.service -n 30 --no-pager
```

Timer cần `enabled`, có thời điểm `NEXT` khoảng 02:00 và thư mục backup phải có file `.sql.gz`. Dùng `sudo gzip -t <ten-file.sql.gz>` để kiểm tra file nén không hỏng.

### 5.13. Playwright và thông báo Telegram

**Đã làm được gì**

Playwright tự chạy lúc 07:00, kiểm thử quy trình thật trên trình duyệt Chromium rồi gửi bản tóm tắt đạt/lỗi tới Telegram. Nếu VM tắt lúc 07:00, timer chạy bù khi VM bật lại.

**Đã làm như thế nào**

`phone-shop-monitor.yml` cài `/usr/local/bin/run-phone-shop-e2e`, service `phone-shop-e2e.service` và timer `phone-shop-e2e.timer`. Token Telegram nằm trong `~/.config/infra/telegram.env` quyền `0600`, không nằm trong Git.

**Kiểm tra**

```bash
systemctl is-enabled phone-shop-e2e.timer
systemctl list-timers phone-shop-e2e.timer --all
sudo journalctl -u phone-shop-e2e.service -n 100 --no-pager
```

Lần chạy ngày 24/10/2026 có 36 test đạt, 8 lỗi và 1 chập chờn. Điều này chứng minh lịch và Playwright đã chạy; các test lỗi phản ánh lỗi ứng dụng hoặc dữ liệu kiểm thử cần xử lý riêng.

Gửi thử Telegram mà không chạy toàn bộ test:

```bash
sudo /usr/local/bin/run-phone-shop-e2e --notification-test
```

Lệnh cần báo đã gửi tin nhắn và bot Telegram phải nhận được tin thử.

### 5.14. CI/CD GitHub Actions

**Đã làm được gì**

Mỗi push vào `main` tự build Spring Boot và Next.js trên GitHub. Khi cả hai build đạt, self-hosted runner trong VM triển khai đúng commit đó bằng Ansible rồi kiểm tra web/API.

**Đã làm như thế nào**

Workflow nằm tại `.github/workflows/ci-cd.yml` của repo Phone Shop. Runner `phone-shop-vm` chạy bằng systemd. Job deploy gọi `/usr/local/sbin/deploy-phone-shop <GITHUB_SHA>`; script dùng `flock` để ngăn hai lần deploy chạy cùng lúc.

**Kiểm tra**

1. Mở <https://github.com/thoa2005/Phone-shop/actions>.
2. Xác nhận ba job Build Spring Boot, Build Next.js và Deploy production VM đều xanh.
3. Trong VM chạy:

```bash
systemctl is-active actions.runner.thoa2005-Phone-shop.phone-shop-vm.service
git -C ~/Phone-shop rev-parse --short HEAD
```

Runner cần trả `active`. Commit trên VM phải trùng commit được ghi trong lần chạy GitHub Actions.

### 5.15. Snapshot VMware

**Đã làm được gì**

VM có snapshot `phone-shop-infra-complete-2026-10-23`, dùng làm điểm quay lại khi thử nghiệm làm hỏng hệ thống.

**Đã làm như thế nào**

Snapshot được tạo bởi VMware Workstation và lưu trạng thái đĩa VM tại thời điểm chụp. Nó không được tạo bởi Ansible và không chạy theo lịch.

**Kiểm tra từ Windows**

```powershell
& 'C:\Program Files\VMware\VMware Workstation\vmrun.exe' -T ws listSnapshots 'D:\Infra\Machine_automation.vmx'
```

Kết quả phải liệt kê tên snapshot. Lệnh này chỉ đọc danh sách, không khôi phục hay thay đổi VM.

## 6. Các file tự động hóa quan trọng

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

## 7. Kiểm tra nhanh mỗi ngày

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

## 8. Kiểm tra CI/CD bằng một commit không đổi file

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

## 9. Xem log

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

## 10. Kiểm tra lịch tự động

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

## 11. Dựng lại cấu hình trên một VM Ubuntu mới

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

## 12. Snapshot VMware và khôi phục

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

## 13. Khi pipeline hoặc ứng dụng bị lỗi

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

## 14. Hoàn tác một lần triển khai lỗi

Không dùng `git reset --hard` trên nhánh chung. Tạo một commit đảo thay đổi rồi push:

```bash
git log --oneline -5
git revert <commit-bi-loi>
git push origin main
```

`git revert` tạo commit mới để đảo nội dung commit lỗi. CI/CD sẽ kiểm tra và tự triển khai commit hoàn tác.

## 15. Bảo mật

- Không commit token GitHub, khóa SSH, mật khẩu MySQL hoặc token Telegram.
- Token đăng ký runner chỉ dùng một lần và file tạm đã bị xóa sau khi đăng ký.
- Runner chỉ được dùng cho job Deploy khi push vào `main`; pull request không chạy trên VM.
- File sudoers chỉ cho tài khoản `vanthoa` gọi `/usr/local/sbin/deploy-phone-shop` không cần nhập mật khẩu.
- Script deploy kiểm tra commit phải là SHA 40 ký tự và dùng khóa `flock` để tránh hai lần deploy chạy cùng lúc.
- Vì repo Phone Shop là public, chỉ người tin cậy mới nên có quyền push hoặc sửa workflow trên nhánh `main`.

## 16. Phần chưa tự động hóa hoặc chưa phù hợp production

- Việc tạo VM VMware mới vẫn làm thủ công.
- IP `192.168.100.4` là IP DHCP trong LAN, chưa phải IP tĩnh và chưa phải địa chỉ Internet công khai.
- Chưa có domain và chứng chỉ HTTPS thật.
- Backup vẫn nằm trong chính VM, chưa sao chép sang máy/ổ lưu trữ khác.
- Chưa có hệ thống giám sát tập trung về CPU, RAM, dung lượng đĩa và cảnh báo dịch vụ ngoài Telegram của Playwright.
- Inventory Ansible hiện chỉ cấu hình `localhost`; chưa có mô hình một máy điều khiển quản lý nhiều server qua SSH.
- Snapshot và tạo VM chưa được nối vào pipeline CI/CD.

Như vậy, hệ thống hiện là một lab tự động hóa khá đầy đủ cho một VM. Nó chưa phải kiến trúc production có khả năng chịu lỗi hoặc mở rộng nhiều máy.

## 17. Các thuật ngữ

- **CI**: tự build và kiểm tra mã nguồn sau khi push hoặc tạo pull request.
- **CD**: tự đưa phiên bản đã qua CI lên máy chạy ứng dụng.
- **Workflow**: file YAML mô tả các job GitHub Actions.
- **Job**: một nhóm bước như build backend, build frontend hoặc deploy.
- **Runner**: máy thực thi job GitHub Actions.
- **Self-hosted runner**: runner do mình quản lý; trong dự án này nó nằm trong VM Ubuntu.
- **Commit SHA**: mã định danh duy nhất của một commit Git.
- **Idempotent**: chạy Ansible nhiều lần vẫn đưa hệ thống về cùng trạng thái mong muốn.
- **Reverse proxy**: Nginx nhận truy cập ở cổng 80 rồi chuyển yêu cầu tới Next.js hoặc Spring Boot.

## 18. Checklist xác nhận toàn bộ hệ thống tốt

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
