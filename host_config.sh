apt update && apt -y upgrade

apt install systemd-container debootstrap zip

reboot

cd /opt/

sudo debootstrap --variant=minbase noble /opt/starfish-demo http://archive.ubuntu.com/ubuntu


curl -O https://files.starfishstorage.com/link/UjZoNdqJpU0YKCGQZEvRsA/download/starfish-offline-bundle-6.7.12947+a219122ea8-ubuntu-24.04.tgz

tar xvzf starfish-offline-bundle-6.7.12947+a219122ea8-ubuntu-24.04.tgz -C /opt/sfrepo

cd /opt/sfrepo/installer/

cat > starfish.keyfile << 'EOF'
# [license]
# username = lab
# expires = 2026-12-31
# all_enabled = True
# enabled =
# disabled =
# proof_of_concept = False
# comment =
keyfile=v3:01234567800123456780012345678001234567800123456780012345678001234567800123456780012345678001234567800123456780012345678001234567800123456780==
EOF

bash install-Starfish.sh -- --sf-offline-installation --sf-repo-url /opt/sfrepo
