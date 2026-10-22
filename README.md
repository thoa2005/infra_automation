# Hạ tầng tự động hóa

Dự án thực hành System Engineer: quản lý mã cấu hình bằng Git và dùng Ansible để cấu hình Nginx trên Ubuntu. VM hiện tại được tạo thủ công trong VMware Workstation; phần tạo VM mới bằng mã chưa hoàn thành.

## Những gì đã tự động hóa

- `ansible/inventory/hosts.ini`: nhóm máy `webservers`. Hiện dùng `localhost` vì Ansible chạy trong chính VM Ubuntu.
- `ansible/playbooks/nginx.yml`: cài Nginx, bật dịch vụ cùng hệ thống và triển khai `ansible/files/index.html`.
- `ansible/files/check-nginx.sh`: kiểm tra HTTP 200 tại `127.0.0.1` mỗi 5 phút qua cron. Kết quả vào system journal với nhãn `infra-health`.
- `scripts/Start-Infrastructure.ps1`: trên Windows, bật VM nếu cần, tìm IP bằng `vmrun`, kết nối SSH, cập nhật repo và chạy playbook.
- `ansible/playbooks/phone-shop-prereqs.yml`: chuẩn bị Java 17, Maven, Node.js, npm, MySQL và Playwright/Chromium cho dự án Phone-shop.
- `ansible/playbooks/phone-shop-monitor.yml`: cài script chạy Playwright, gửi kết quả qua Telegram và tạo lịch systemd hằng ngày.
- `ansible/playbooks/phone-shop-deploy.yml`: tạo database/tài khoản MySQL, build Spring Boot và Next.js, chạy hai dịch vụ bằng systemd, rồi cấu hình Nginx reverse proxy.
- `tests/`: bài kiểm thử trình duyệt mẫu. Repo Phone-shop hiện chưa có bài e2e; bài này chỉ xác nhận trang web trả HTTP 200.

## Chạy trên VM hiện tại

Điều kiện: VMware Workstation và SSH key từ Windows vào VM đã được thiết lập. Chạy PowerShell tại thư mục repo trên Windows:

```powershell
.\scripts\Start-Infrastructure.ps1
```

Script sẽ hỏi mật khẩu `sudo` trong terminal khi Ansible cần quyền quản trị; script không lưu mật khẩu. Khi hoàn tất, mở URL mà script in ra. Chạy lại sẽ cho `changed=0` nếu cấu hình không đổi.

Muốn chỉ kiểm tra VM, IP và SSH mà chưa chạy Ansible, thêm tham số `-CheckOnly`.

Trên Ubuntu có thể chạy playbook trực tiếp:

```bash
cd ~/infra_automation
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/nginx.yml -K
```

Ubuntu 26.04 trong lab dùng `sudo-rs`. Inventory chỉ định `/usr/bin/sudo.ws` để Ansible nhận đúng dấu nhắc mật khẩu.

Để cài môi trường Phone-shop trên Ubuntu, chạy trong thư mục repo:

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-prereqs.yml -K
```

`-i` chọn inventory; `-K` hỏi mật khẩu sudo. Playbook cài Java và Maven để build backend, Node.js và npm để build frontend, MySQL cho dữ liệu, cùng Playwright và Chromium cho test. Nó chưa tạo database, chưa build/chạy Phone-shop và chưa đặt lịch hay gửi Telegram.

Kiểm tra môi trường và chạy bài test mẫu:

```bash
java -version
mvn -version
node --version
npm --version
mysql --version
cd /opt/phone-shop-tests
npx playwright --version
npm test
```

`npm test` chạy script `playwright test` trong `package.json` và mở trang Nginx hiện tại tại `http://127.0.0.1`. Khi ứng dụng Phone-shop được triển khai, đổi URL và thêm các bài test nghiệp vụ.

## Thông báo Telegram và lịch kiểm thử

Tạo file riêng tư `/home/vanthoa/.config/infra/telegram.env` trên VM:

```bash
TELEGRAM_TOKEN=token-cua-bot
TELEGRAM_CHAT_ID=id-cuoc-tro-chuyen
```

Không commit file này vào Git. Khóa quyền đọc và cài service/timer:

```bash
chmod 600 ~/.config/infra/telegram.env
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-monitor.yml -K
sudo /usr/local/bin/run-phone-shop-e2e --notification-test
```

Playbook mặc định chỉ cài timer và giữ nó ở trạng thái tắt vì ứng dụng chưa được triển khai. Sau khi backend, frontend và database đã chạy ổn, bật lịch 07:00 hằng ngày:

```bash
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-monitor.yml -K -e phone_shop_monitor_enabled=true
systemctl list-timers phone-shop-e2e.timer
journalctl -u phone-shop-e2e.service -n 100 --no-pager
```

`-e phone_shop_monitor_enabled=true` ghi đè biến mặc định để bật timer. `list-timers` cho biết lần chạy kế tiếp; `journalctl` xem kết quả và lỗi của lần chạy gần đây.

## Triển khai Phone Shop

Cài collection quản lý MySQL một lần cho tài khoản Ansible, sau đó chạy playbook:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/phone-shop-deploy.yml -K
```

Playbook sinh mật khẩu database và khóa JWT tại `~/.config/infra/`, tạo `/etc/phone-shop/backend.env` với quyền `0600`, build mã nguồn và tạo ba dịch vụ `phone-shop-backend`, `phone-shop-frontend`, `nginx`. Các giá trị bí mật không được commit vào Git.

Kiểm tra trạng thái sau khi triển khai:

```bash
systemctl status phone-shop-backend phone-shop-frontend nginx --no-pager
curl -I http://127.0.0.1/
curl http://127.0.0.1/api/products
```

Sau khi chạy playbook, kiểm tra thủ công trên Ubuntu:

```bash
sudo /usr/local/bin/check-nginx
sudo journalctl -t infra-health -n 10 --no-pager
sudo crontab -l
```

Lệnh thứ nhất kiểm tra HTTP ngay; lệnh thứ hai xem 10 bản ghi gần nhất; lệnh thứ ba xác nhận lịch cron. Nhật ký lỗi hiện chỉ lưu tại máy, chưa gửi cảnh báo ra ngoài.

## Chưa hoàn thành

- Tạo VM mới từ một nguồn Ubuntu sạch bằng mã.
- Dùng một máy điều khiển Ansible cấu hình VM khác qua SSH.
- Triển khai backend, frontend và schema MySQL cho Phone-shop; bật lịch Playwright sau khi ứng dụng chạy ổn; CI và bài dựng lại hạ tầng từ đầu.
