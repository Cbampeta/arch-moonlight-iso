#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/work"
OUT_DIR="${SCRIPT_DIR}/out"
PROFILE_DIR="${SCRIPT_DIR}/build-profile"
VENTOY_DIR="/run/media/${USER}/Ventoy"
ISO_DEST_NAME="arch-moonlight-thinclient.iso"
LUKS_DEST_NAME="arch-moonlight-state.luks"

# Language selection at startup (English by default, French optional)
echo "Select language / Choisissez la langue :"
echo "  [1] English (default)"
echo "  [2] Francais"
read -rp "Choice / Choix [1]: " LANG_INPUT
case "${LANG_INPUT,,}" in
    2|fr|french|francais|français)
        SCRIPT_LANG="fr"
        DEFAULT_KEYMAP="fr"
        ;;
    *)
        SCRIPT_LANG="en"
        DEFAULT_KEYMAP="us"
        ;;
esac
export SCRIPT_LANG

msg() {
    local en="$1"
    local fr="$2"
    if [[ "${SCRIPT_LANG}" == "fr" ]]; then
        printf '%s\n' "${fr}"
    else
        printf '%s\n' "${en}"
    fi
}

echo ""
echo "================================================================"
echo "  Arch Moonlight ThinClient (Moonlight + Tailscale + USB/IP)    "
msg \
    "  ISO Builder + Ventoy Deployment + Host USB/IP Receiver        " \
    "  Constructeur ISO + Deploiement Ventoy + Recepteur Hote        "
echo "================================================================"
echo ""

# 1. Install build dependencies on this PC
msg \
    "[1/7] Checking and installing build tools (archiso, usbip, cryptsetup, openssl)..." \
    "[1/7] Verification et installation des outils (archiso, usbip, cryptsetup, openssl)..."
sudo pacman -S --needed --noconfirm archiso usbip cryptsetup openssl

# 2. Configure ISO keyboard layout and login password ('thin' and 'root')
echo ""
msg \
    "[2/7] ISO configuration (keyboard layout & login password for 'thin' and 'root'):" \
    "[2/7] Configuration de l'ISO (clavier et mot de passe pour 'thin' et 'root') :"

if [[ "${SCRIPT_LANG}" == "fr" ]]; then
    read -rp "  Disposition clavier ISO (ex: fr, us, de, uk) [${DEFAULT_KEYMAP}] : " ISO_KEYMAP
else
    read -rp "  ISO keyboard layout (e.g. us, fr, de, uk) [${DEFAULT_KEYMAP}]: " ISO_KEYMAP
fi
ISO_KEYMAP="${ISO_KEYMAP:-${DEFAULT_KEYMAP}}"

while true; do
    if [[ "${SCRIPT_LANG}" == "fr" ]]; then
        read -rsp "  Nouveau mot de passe ISO : " ISO_PASS1
        echo ""
        read -rsp "  Confirmer le mot de passe : " ISO_PASS2
        echo ""
    else
        read -rsp "  New ISO password: " ISO_PASS1
        echo ""
        read -rsp "  Confirm password: " ISO_PASS2
        echo ""
    fi
    if [[ -z "${ISO_PASS1}" ]]; then
        msg \
            "  [!] Password cannot be empty." \
            "  [!] Le mot de passe ne peut pas etre vide."
    elif [[ "${ISO_PASS1}" != "${ISO_PASS2}" ]]; then
        msg \
            "  [!] Passwords do not match." \
            "  [!] Les mots de passe ne correspondent pas."
    else
        break
    fi
done
PASS_HASH="$(printf '%s' "${ISO_PASS1}" | openssl passwd -6 -stdin)"
unset ISO_PASS1 ISO_PASS2

# 3. Prepare archiso profile from releng
echo ""
msg \
    "[3/7] Preparing archiso profile (keymap: ${ISO_KEYMAP})..." \
    "[3/7] Preparation du profil archiso (clavier : ${ISO_KEYMAP})..."
sudo rm -rf "${PROFILE_DIR}" "${WORK_DIR}"
mkdir -p "${OUT_DIR}"
cp -a /usr/share/archiso/configs/releng "${PROFILE_DIR}"

# Replace package list
cp "${SCRIPT_DIR}/packages.x86_64" "${PROFILE_DIR}/packages.x86_64"

# Remove releng root autologin
rm -rf "${PROFILE_DIR}/airootfs/etc/systemd/system/getty@tty1.service.d"

# Remove unneeded releng network/live services (we use NetworkManager)
rm -f \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/multi-user.target.wants/iwd.service" \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/multi-user.target.wants/reflector.service" \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/multi-user.target.wants/choose-mirror.service" \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/multi-user.target.wants/systemd-networkd.service" \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service" \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/sockets.target.wants/systemd-networkd.socket" \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/dbus-org.freedesktop.resolve1.service" \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/sysinit.target.wants/systemd-resolved.service" \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/cloud-init.target.wants/"* \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/multi-user.target.wants/cloud-init.target" \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/multi-user.target.wants/livecd-talk.service" \
    2>/dev/null || true

# Copy custom overlay
cp -a "${SCRIPT_DIR}/overlay/." "${PROFILE_DIR}/airootfs/"
rm -f "${PROFILE_DIR}/airootfs/INDEX.md"

# Apply selected keyboard layout to console and X11
printf 'KEYMAP=%s\n' "${ISO_KEYMAP}" > "${PROFILE_DIR}/airootfs/etc/vconsole.conf"
cat > "${PROFILE_DIR}/airootfs/etc/X11/xorg.conf.d/00-keyboard.conf" <<EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "${ISO_KEYMAP}"
EndSection
EOF

# Enable systemd services inside the ISO
WANTS_DIR="${PROFILE_DIR}/airootfs/etc/systemd/system/multi-user.target.wants"
mkdir -p "${WANTS_DIR}"
ln -sf /usr/lib/systemd/system/NetworkManager.service "${WANTS_DIR}/NetworkManager.service"
ln -sf /usr/lib/systemd/system/tailscaled.service "${WANTS_DIR}/tailscaled.service"
ln -sf /usr/lib/systemd/system/usbipd.service "${WANTS_DIR}/usbipd.service"
ln -sf /usr/lib/systemd/system/sshd.service "${WANTS_DIR}/sshd.service"
ln -sf /etc/systemd/system/thin-lock-state.service "${WANTS_DIR}/thin-lock-state.service"
ln -sf /etc/systemd/system/usbip-initial-scan.service "${WANTS_DIR}/usbip-initial-scan.service"

# Enable NetworkManager-wait-online for clean boot ordering
mkdir -p "${PROFILE_DIR}/airootfs/etc/systemd/system/network-online.target.wants"
ln -sf /usr/lib/systemd/system/NetworkManager-wait-online.service \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service"

# Configure root and thin (UID 1000) accounts with the chosen password
# System groups (wheel, audio, video, input, network) are assigned via /etc/sysusers.d/thin.conf
cat > "${PROFILE_DIR}/airootfs/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/usr/bin/bash
thin:x:1000:1000:ThinClient User:/home/thin:/usr/bin/bash
EOF

cat > "${PROFILE_DIR}/airootfs/etc/shadow" <<EOF
root:${PASS_HASH}:19900:0:99999:7:::
thin:${PASS_HASH}:19900:0:99999:7:::
EOF
unset PASS_HASH

# Force copytoram=n in boot menus (saves ~1 GB RAM on low-memory PCs)
for cfg in \
    "${PROFILE_DIR}"/syslinux/*.cfg \
    "${PROFILE_DIR}"/efiboot/loader/entries/*.conf \
    "${PROFILE_DIR}"/grub/*.cfg; do
    [[ -f "${cfg}" ]] || continue
    if grep -q "archisosearchuuid=" "${cfg}" && ! grep -q "copytoram=" "${cfg}"; then
        sed -i 's/archisosearchuuid=\([^ ]*\)/archisosearchuuid=\1 copytoram=n/g' "${cfg}"
    fi
done

# Update profiledef.sh (ISO metadata & script permissions)
sed -i 's/^iso_name=.*/iso_name="arch-moonlight-thinclient"/' "${PROFILE_DIR}/profiledef.sh"
sed -i 's/^iso_label=.*/iso_label="ARCH_MOONLIGHT"/' "${PROFILE_DIR}/profiledef.sh"
sed -i 's/^iso_publisher=.*/iso_publisher="Arch Moonlight ThinClient"/' "${PROFILE_DIR}/profiledef.sh"
sed -i 's/^iso_application=.*/iso_application="Arch Linux Moonlight + Tailscale + USB\/IP"/' "${PROFILE_DIR}/profiledef.sh"

# Append custom file permissions to file_permissions in profiledef.sh
python3 - "${PROFILE_DIR}/profiledef.sh" <<'PYEOF'
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

extra_perms = """
  ["/etc/sudoers.d/10-thin"]="0:0:440"
  ["/home/thin"]="1000:1000:750"
  ["/home/thin/.bash_profile"]="1000:1000:644"
  ["/home/thin/.bashrc"]="1000:1000:644"
  ["/usr/local/bin/thin-unlock-state"]="0:0:755"
  ["/usr/local/bin/thin-lock-state"]="0:0:755"
  ["/usr/local/bin/thin-xsession"]="0:0:755"
  ["/usr/local/bin/usbip-auto-export.sh"]="0:0:755"
  ["/usr/local/bin/usbip-status"]="0:0:755"
  ["/usr/local/bin/usbip-scan"]="0:0:755"
"""

idx = content.find("file_permissions=(")
if idx != -1:
    end_idx = content.find("\n)", idx)
    if end_idx != -1:
        content = content[:end_idx] + extra_perms + content[end_idx:]

with open(path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF

# 4. Build the ISO with mkarchiso
echo ""
msg \
    "[4/7] Building ISO with mkarchiso (this takes a few minutes)..." \
    "[4/7] Construction de l'ISO avec mkarchiso (cela prend quelques minutes)..."
rm -f "${OUT_DIR}"/*.iso
sudo mkarchiso -v -w "${WORK_DIR}" -o "${OUT_DIR}" "${PROFILE_DIR}"

BUILT_ISO="$(ls -1t "${OUT_DIR}"/arch-moonlight-thinclient-*.iso | head -n1)"
msg \
    "[OK] ISO built: ${BUILT_ISO}" \
    "[OK] ISO construite : ${BUILT_ISO}"

# 5. Deploy to Ventoy USB drive
echo ""
msg \
    "[5/7] Deploying to Ventoy USB drive (${VENTOY_DIR})..." \
    "[5/7] Deploiement sur la cle Ventoy (${VENTOY_DIR})..."
if [[ -d "${VENTOY_DIR}" ]]; then
    msg \
        "  Copying ISO to ${VENTOY_DIR}/${ISO_DEST_NAME}..." \
        "  Copie de l'ISO vers ${VENTOY_DIR}/${ISO_DEST_NAME}..."
    cp -f "${BUILT_ISO}" "${VENTOY_DIR}/${ISO_DEST_NAME}"

    # Ventoy configuration to allow remounting the Ventoy partition from inside the live ISO
    mkdir -p "${VENTOY_DIR}/ventoy"
    if [[ ! -f "${VENTOY_DIR}/ventoy/ventoy.json" ]]; then
        cat > "${VENTOY_DIR}/ventoy/ventoy.json" <<'EOF'
{
    "control": [
        { "VTOY_LINUX_REMOUNT": "1" }
    ]
}
EOF
        msg \
            "  [OK] Created ${VENTOY_DIR}/ventoy/ventoy.json." \
            "  [OK] ${VENTOY_DIR}/ventoy/ventoy.json cree."
    else
        msg \
            "  [*] ${VENTOY_DIR}/ventoy/ventoy.json already exists (ensure VTOY_LINUX_REMOUNT is enabled if Ventoy <= 1.1.00)." \
            "  [*] ${VENTOY_DIR}/ventoy/ventoy.json existe deja (verifie que VTOY_LINUX_REMOUNT est actif si Ventoy <= 1.1.00)."
    fi

    # 6. Create LUKS2 encrypted persistence container (if it doesn't already exist)
    echo ""
    msg \
        "[6/7] LUKS2 encrypted persistence container (${LUKS_DEST_NAME})..." \
        "[6/7] Conteneur de persistance chiffre LUKS2 (${LUKS_DEST_NAME})..."
    LUKS_PATH="${VENTOY_DIR}/${LUKS_DEST_NAME}"
    if [[ -f "${LUKS_PATH}" ]]; then
        msg \
            "  [*] ${LUKS_PATH} already exists: kept intact (your Tailscale/Moonlight/Wi-Fi configs are preserved!)." \
            "  [*] ${LUKS_PATH} existe deja : conserve tel quel (tes configs Tailscale/Moonlight/Wi-Fi sont intactes !)."
    else
        msg \
            "  Creating a 128 MB LUKS2 encrypted container on the Ventoy drive." \
            "  Creation d'un conteneur chiffre LUKS2 de 128 Mo sur la cle Ventoy."
        msg \
            "  Choose the passphrase that will protect your Tailscale, Moonlight, and Wi-Fi credentials:" \
            "  Choisis la phrase de passe qui protegera tes cles Tailscale, Moonlight et Wi-Fi :"
        dd if=/dev/zero of="${LUKS_PATH}" bs=1M count=128 status=progress
        sudo cryptsetup luksFormat --type luks2 "${LUKS_PATH}"
        msg \
            "  Initializing ext4 filesystem inside the container..." \
            "  Initialisation du systeme de fichiers ext4 a l'interieur du conteneur..."
        sudo cryptsetup open "${LUKS_PATH}" thinclient_state_init
        sudo mkfs.ext4 -L thinclient_state /dev/mapper/thinclient_state_init
        TMP_MNT="$(mktemp -d)"
        sudo mount /dev/mapper/thinclient_state_init "${TMP_MNT}"
        sudo mkdir -p \
            "${TMP_MNT}/tailscale" \
            "${TMP_MNT}/NetworkManager" \
            "${TMP_MNT}/moonlight" \
            "${TMP_MNT}/custom"
        sudo chmod 700 "${TMP_MNT}/NetworkManager"
        sudo chown -R 1000:1000 "${TMP_MNT}/moonlight"
        sudo umount "${TMP_MNT}"
        rmdir "${TMP_MNT}"
        sudo cryptsetup close thinclient_state_init
        msg \
            "  [OK] Encrypted container created: ${LUKS_PATH}" \
            "  [OK] Conteneur chiffre cree : ${LUKS_PATH}"
    fi
    sync
else
    msg \
        "  [!] Ventoy drive not found at ${VENTOY_DIR}." \
        "  [!] Cle Ventoy non trouvee sur ${VENTOY_DIR}."
    msg \
        "      You can manually copy ${BUILT_ISO} to your Ventoy USB drive." \
        "      Tu pourras copier manuellement ${BUILT_ISO} sur ta cle Ventoy."
fi

# 7. Optionally install the automatic USB/IP receiver on this host PC
echo ""
msg \
    "[7/7] Automatic USB/IP receiver on this host PC..." \
    "[7/7] Recepteur USB/IP automatique sur ce PC hote..."
if [[ "${SCRIPT_LANG}" == "fr" ]]; then
    read -rp "  Installer le service usbip-auto-attach sur ce PC hote ? [O/n] : " INSTALL_HOST
else
    read -rp "  Install usbip-auto-attach service on this host PC? [Y/n]: " INSTALL_HOST
fi
case "${INSTALL_HOST,,}" in
    n|no|non)
        msg \
            "  [*] Skipped host USB/IP receiver setup. You can run ./host-setup/install-host-usbip.sh later." \
            "  [*] Installation hote ignoree. Tu pourras lancer ./host-setup/install-host-usbip.sh plus tard."
        ;;
    *)
        bash "${SCRIPT_DIR}/host-setup/install-host-usbip.sh"
        ;;
esac

# Clean up temporary build directories
sudo rm -rf "${WORK_DIR}"

echo ""
echo "================================================================"
msg \
    "  DONE!                                                         " \
    "  TERMINE !                                                     "
echo "================================================================"
if [[ "${SCRIPT_LANG}" == "fr" ]]; then
    echo "  ISO       : ${VENTOY_DIR}/${ISO_DEST_NAME}"
    echo "  Stockage  : ${VENTOY_DIR}/${LUKS_DEST_NAME} (chiffre LUKS2)"
    echo "  Login ISO : utilisateur 'thin' (ou 'root') + ton mot de passe"
    echo ""
    echo "  Au 1er demarrage sur l'ancien PC :"
    echo "   1. Boote sur arch-moonlight-thinclient.iso dans Ventoy"
    echo "   2. Connecte-toi en 'thin' sur TTY1 -> deverrouille le conteneur LUKS"
    echo "   3. Fais Ctrl+Alt+F2, connecte-toi en 'thin' :"
    echo "      - wifi    (connecte ton Wi-Fi ou cable Ethernet)"
    echo "      - tsup    (connecte ton compte Tailscale une seule fois)"
    echo "   4. Retourne sur Moonlight avec Ctrl+Alt+F1 et appaire ton PC hote (Sunshine) !"
    echo "   5. Des que tu branches une cle USB / manette / etc. sur l'ancien PC,"
    echo "      elle apparaitra automatiquement sur le PC hote via USB/IP + Tailscale !"
else
    echo "  ISO       : ${VENTOY_DIR}/${ISO_DEST_NAME}"
    echo "  State     : ${VENTOY_DIR}/${LUKS_DEST_NAME} (LUKS2 encrypted)"
    echo "  ISO Login : user 'thin' (or 'root') + your password"
    echo ""
    echo "  First boot on your thin client PC:"
    echo "   1. Boot arch-moonlight-thinclient.iso from Ventoy"
    echo "   2. Log in as 'thin' on TTY1 -> unlock the LUKS container"
    echo "   3. Press Ctrl+Alt+F2 and log in as 'thin':"
    echo "      - wifi    (connect Wi-Fi or plug in Ethernet)"
    echo "      - tsup    (authenticate Tailscale once)"
    echo "   4. Switch back to Moonlight with Ctrl+Alt+F1 and pair your Sunshine host!"
    echo "   5. Any USB drive / controller / peripheral plugged into the thin client"
    echo "      will automatically attach to your host PC over USB/IP + Tailscale!"
fi
echo "================================================================"
