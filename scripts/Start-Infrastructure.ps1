param(
    [string]$VmPath = 'D:\Infra\Machine_automation.vmx',
    [string]$VmrunPath = 'C:\Program Files\VMware\VMware Workstation\vmrun.exe',
    [string]$SshUser = 'vanthoa',
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $VmPath -PathType Leaf)) {
    throw "Khong tim thay VM: $VmPath"
}
if (-not (Test-Path -LiteralPath $VmrunPath -PathType Leaf)) {
    throw "Khong tim thay vmrun: $VmrunPath"
}

$runningVms = & $VmrunPath -T ws list
if ($LASTEXITCODE -ne 0) {
    throw 'Khong the doc danh sach VM tu vmrun.'
}

if (-not ($runningVms | Where-Object { $_.Trim() -eq $VmPath })) {
    Write-Host 'Dang bat VM...'
    & $VmrunPath -T ws start $VmPath nogui
    if ($LASTEXITCODE -ne 0) {
        throw 'Khong the bat VM.'
    }
}

$ip = $null
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    $candidate = & $VmrunPath -T ws getGuestIPAddress $VmPath 2>$null | Select-Object -First 1
    if ($candidate) {
        $candidate = $candidate.Trim()
    }
    if ($candidate -match '^(?:\d{1,3}\.){3}\d{1,3}$' -and $candidate -ne '0.0.0.0') {
        $ip = $candidate
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $ip) {
    throw 'VM chua co IP sau 60 giay. Kiem tra VMware Tools va mang cua VM.'
}

$sshTarget = "${SshUser}@${ip}"
Write-Host "IP cua VM: $ip"

$sshReady = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    & ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=5 $sshTarget 'true' 2>$null
    if ($LASTEXITCODE -eq 0) {
        $sshReady = $true
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $sshReady) {
    throw "Khong SSH duoc vao $sshTarget. Kiem tra mang, SSH key va known_hosts."
}

if ($CheckOnly) {
    Write-Host 'VM, IP va SSH da san sang. Chua chay git pull hoac Ansible.'
    return
}

Write-Host 'Dang cap nhat repo va chay Ansible. Mat khau sudo se duoc hoi trong terminal.'
$remoteCommand = 'cd ~/infra_automation && git pull --ff-only && ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/nginx.yml -K'
& ssh -tt -o BatchMode=yes -o StrictHostKeyChecking=yes $sshTarget $remoteCommand
if ($LASTEXITCODE -ne 0) {
    throw 'Ansible khong chay thanh cong. Xem loi o phia tren.'
}

Write-Host "Hoan tat. Mo http://$ip tren trinh duyet de kiem tra."
