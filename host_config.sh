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
# username = dmedeiros_lab
# expires = 2026-12-31
# all_enabled = True
# enabled =
# disabled =
# proof_of_concept = False
# comment =
keyfile=v3:YR8eUA65UVQ6fnklxioQ4vquD3WfvvtJeKAS6EDi2QEdVSbW85okhsR0SKn++uV0IHufSXaiPwUWIoGIHsbV1y3GlkUAZ4V6g6o1A3/0SBGtoiOlfB43+4se45d2vf7wY/10L0S0NAmAPct6xdmts6VVIuM5Oemnnt/pTqcfTYow4ARMWL54JQdExcnQVtTyQzttUTG9nRcAc1BZT+x9pILEfHDPm6yo8uOoaGJCvA==
EOF

bash install-Starfish.sh -- --sf-offline-installation --sf-repo-url /opt/sfrepo
