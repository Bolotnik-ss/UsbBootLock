#!/bin/bash

# Скрипт установки UsbBootLock
# Этот скрипт автоматизирует процесс установки скрипта защиты загрузки.
# Он заменяет плейсхолдер серийного номера и настраивает систему.

# --- Переменные ---
SCRIPT_NAME="usb-lock.sh"
INSTALL_SCRIPT_PATH="./usb-lock.sh"
# Определяем путь установки в зависимости от дистрибутива
INITRAMFS_TARGET_DIR=""
INITRAMFS_UPDATE_CMD=""

# Проверяем, установлен ли пакет 'usbutils' (для lsusb)
if ! command -v lsusb &> /dev/null
then
    echo "Ошибка: пакет 'usbutils' не найден. Пожалуйста, установите его."
    echo "Для Debian/Ubuntu: sudo apt install usbutils"
    echo "Для Fedora/Arch: sudo dnf install usbutils (или pacman -S usbutils)"
    exit 1
fi

# --- Определение команды обновления initramfs и пути установки для разных дистрибутивов ---
# Проверяем наличие mkinitcpio (Arch Linux, Manjaro)
if command -v mkinitcpio &> /dev/null;
then
    INITRAMFS_TARGET_DIR="/etc/initcpio/hooks/"
    INITRAMFS_UPDATE_CMD="sudo mkinitcpio -P"
    HOOK_FILE_NAME="usb-lock.sh"
    echo "Обнаружена система Arch Linux (или совместимая). Используем mkinitcpio."
	# Содержимое хука для mkinitcpio
    HOOK_CONTENT="
build() {
    add_module usb_storage
    add_binary usb-lock.sh
}

help() {
    echo "Этот хук добавляет скрипт usb-lock.sh для проверки USB-устройства при загрузке."
}
"

elif command -v dracut &> /dev/null;
then
    INITRAMFS_TARGET_DIR="/usr/lib/dracut/modules.d/90usblock/"
    INITRAMFS_UPDATE_CMD="sudo dracut -f"
    HOOK_FILE_NAME="90usblock"
    echo "Обнаружена система Fedora/RHEL (или совместимая). Используем dracut."
else
    # По умолчанию предполагаем Debian/Ubuntu или совместимый с initramfs-tools
    INITRAMFS_TARGET_DIR="/etc/initramfs-tools/scripts/init-bottom/"
    INITRAMFS_UPDATE_CMD="sudo update-initramfs -u"
    HOOK_FILE_NAME="usb-lock.sh"
    echo "Предупреждение: Не удалось точно определить систему или менеджер initramfs.
    Используется команда по умолчанию для initramfs-tools (Debian/Ubuntu).
    Возможно, потребуется ручное обновление initramfs или установка соответствующих пакетов."
    # Проверяем, установлен ли initramfs-tools
    if ! command -v update-initramfs &> /dev/null;
    then
        echo "Ошибка: initramfs-tools не найден. Установите его или настройте вручную."
        exit 1
    fi
fi

# --- Получение серийного номера USB ---
SERIAL_NUMBER=""
# Если серийный номер передан как первый аргумент скрипта
if [ "$1" ]; then
    SERIAL_NUMBER="$1"
    echo "Используется серийный номер из аргумента: $SERIAL_NUMBER"
else
    echo "Для продолжения установки необходимо ввести серийный номер вашего USB-накопителя."
    echo "Вы можете получить его, подключив накопитель и выполнив команду 'sudo lsusb -v -d <VendorID>:<ProductID> | grep iSerial'."
    read -p "Введите серийный номер USB: " SERIAL_NUMBER
fi

# Проверка, что серийный номер не пуст
if [ -z "$SERIAL_NUMBER" ]; then
    echo "Ошибка: Серийный номер USB не может быть пустым. Установка отменена."
    exit 1
fi

# --- Подготовка скрипта ---
# Проверяем, существует ли основной скрипт UsbBootLock
if [ ! -f "$INSTALL_SCRIPT_PATH" ]; then
    echo "Ошибка: Основной скрипт '$INSTALL_SCRIPT_PATH' не найден. Установка не может быть продолжена."
    exit 1
fi

# Загружаем содержимое основного скрипта.
SCRIPT_CONTENT=$(cat "$INSTALL_SCRIPT_PATH")

# Заменяем плейсхолдер "YOUR_SERIAL_NUMBER" на введенное значение.
# Используем sed с заменой "YOUR_SERIAL_NUMBER" на введенный SERIAL_NUMBER.
# Важно: экранируем любые специальные символы в SERIAL_NUMBER, если они есть (хотя для серийников это маловероятно).
UPDATED_SCRIPT_CONTENT=$(echo "$SCRIPT_CONTENT" | sed "s/SERIAL_NUMBER=\"YOUR_SERIAL_NUMBER\"/SERIAL_NUMBER=\"$SERIAL_NUMBER\"/")

# --- Установка ---

# Создаем директорию для установки, если она не существует.
if [ ! -d "$INITRAMFS_TARGET_DIR" ]; then
    echo "Создание директории: $INITRAMFS_TARGET_DIR"
    sudo mkdir -p "$INITRAMFS_TARGET_DIR"
    if [ $? -ne 0 ]; then
        echo "Ошибка: Не удалось создать директорию $INITRAMFS_TARGET_DIR. Возможно, нужны права sudo."
        exit 1
    fi
fi

# Записываем обновленный скрипт в целевую директорию.
echo "Установка скрипта $SCRIPT_NAME в $INITRAMFS_TARGET_DIR..."
echo "$UPDATED_SCRIPT_CONTENT" | sudo tee "$INITRAMFS_TARGET_DIR/$HOOK_FILE_NAME" > /dev/null
if [ $? -ne 0 ]; then
    echo "Ошибка: Не удалось записать скрипт в $INITRAMFS_TARGET_DIR. Возможно, нужны права sudo."
    exit 1
fi

# Устанавливаем права на выполнение для скрипта.
sudo chmod +x "$INITRAMFS_TARGET_DIR/$HOOK_FILE_NAME"

# Если используется mkinitcpio, создаем файл хука (если он отличается от основного скрипта)
if [[ "$HOOK_FILE_NAME" == "usb-lock.sh" && -n "$HOOK_CONTENT" ]]; then
    echo "Создание файла хука mkinitcpio..."
    echo "$HOOK_CONTENT" | sudo tee "$INITRAMFS_TARGET_DIR/$HOOK_FILE_NAME" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Ошибка: Не удалось записать хук mkinitcpio в $INITRAMFS_TARGET_DIR."
        exit 1
    fi
    sudo chmod +x "$INITRAMFS_TARGET_DIR/$HOOK_FILE_NAME"
fi

# Обновляем initramfs.
echo "Обновление initramfs с помощью команды: $INITRAMFS_UPDATE_CMD"
$INITRAMFS_UPDATE_CMD
if [ $? -ne 0 ]; then
    echo "Ошибка: Не удалось обновить initramfs. Пожалуйста, проверьте вывод команды и устраните проблему."
    echo "Возможно, вам потребуется вручную пересобрать initramfs."
    exit 1
fi

echo ""
echo "Установка UsbBootLock завершена успешно!"
echo "Перезагрузите систему, чтобы применить изменения."