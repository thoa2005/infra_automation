# Hạ tầng tự động hóa

Dự án thực hành System Engineer: quản lý mã cấu hình bằng Git và dùng Ansible để cấu hình Nginx trên Ubuntu. VM hiện tại được tạo thủ công trong VMware Workstation; phần tạo VM mới bằng mã chưa hoàn thành.

## Những gì đã tự động hóa

- `ansible/inventory/hosts.ini`: nhóm máy `webservers`. Hiện dùng `localhost` vì Ansible chạy trong chính VM Ubuntu.
- `ansible/playbooks/nginx.yml`: cài Nginx, bật dịch vụ cùng hệ thống và triển khai `ansible/files/index.html`.
- `ansible/files/check-nginx.sh`: kiểm tra HTTP 200 tại `127.0.0.1` mỗi 5 phút qua cron. Kết quả vào system journal với nhãn `infra-health`.
- `scripts/Start-Infrastructure.ps1`: trên Windows, bật VM nếu cần, tìm IP bằng `vmrun`, kết nối SSH, cập nhật repo và chạy playbook.

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
- Gửi cảnh báo khi dịch vụ lỗi, CI và bài dựng lại hạ tầng từ đầu.
