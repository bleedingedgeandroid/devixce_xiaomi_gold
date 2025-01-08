#!/bin/bash
#
# SPDX-FileCopyrightText: 2016 The CyanogenMod Project
# SPDX-FileCopyrightText: 2017-2024 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

set -e

DEVICE=gold
VENDOR=xiaomi

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_FIRMWARE=
KANG=
SECTION=
CARRIER_SKIP_FILES=()

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --only-firmware)
            ONLY_FIRMWARE=true
            ;;
        -n | --no-cleanup)
            CLEAN_VENDOR=false
            ;;
        -k | --kang)
            KANG="--kang"
            ;;
        -s | --section)
            SECTION="${2}"
            shift
            CLEAN_VENDOR=false
            ;;
        *)
            SRC="${1}"
            ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

symlink_fixup(){
	[ "${SRC}" != "adb" ] && {
		local dir="$(dirname ${SRC}/${1})"
		local fname="$(basename ${SRC}/${1})"
		local plat="$(grep 'ro.board.platform' ${SRC}/vendor/build.prop | cut -d= -f2 | head -1)"
		local fpath="${dir}/${plat}/${fname}"
		[ -f "${fpath}" ] && {
			rm -rf "${2}"
			cp -f "${fpath}" "${2}"
		}
	}
}
export -f symlink_fixup

function blob_fixup {
	case "$1" in
		system_ext/lib*/libsink.so)
			grep -q "libshim_sink.so" "${2}" || \
			"${PATCHELF}" --add-needed "libshim_sink.so" "${2}"
			;;
		system_ext/lib*/libsource.so)
			grep -q libui_shim.so "${2}" || \
			"${PATCHELF}" --add-needed libui_shim.so "${2}"
			;;
		vendor/bin/hw/android.hardware.gnss-service.mediatek | \
		vendor/lib*/hw/android.hardware.gnss-impl-mediatek.so)
			grep -q "android.hardware.gnss-V1-ndk_platform.so" "${2}" && \
			"${PATCHELF}" --replace-needed "android.hardware.gnss-V1-ndk_platform.so" "android.hardware.gnss-V1-ndk.so" "${2}"
			;;
		vendor/bin/hw/android.hardware.media.c2@1.2-mediatek-64b)
			grep -q "libavservices_minijail_vendor.so" "${2}" && \
			"${PATCHELF}" --replace-needed "libavservices_minijail_vendor.so" "libavservices_minijail.so" "${2}"
			grep -q "libstagefright_foundation-v33.so" "${2}" || \
			"${PATCHELF}" --add-needed "libstagefright_foundation-v33.so" "${2}"
			;;
		vendor/bin/hw/vendor.mediatek.hardware.mtkpower@1.0-service)
			grep -q "android.hardware.power-V2-ndk_platform.so" "${2}" && \
			"${PATCHELF}" --replace-needed "android.hardware.power-V2-ndk_platform.so" "android.hardware.power-V2-ndk.so" "${2}"
			;;
		vendor/bin/mnld | vendor/lib*/libaalservice.so | vendor/lib*/libcam.utils.sensorprovider.so)
			grep -q "libshim_sensors.so" "${2}" || \
			"${PATCHELF}" --add-needed "libshim_sensors.so" "${2}"
			;;
		vendor/etc/init/android.hardware.neuralnetworks@1.3-service-mtk-neuron.rc)
			sed -i 's/start/enable/' "${2}"
			;;
		vendor/etc/init/vendor.mediatek.hardware.mtkpower@1.0-service.rc)
			echo "$(cat ${2}) input" > "${2}"
			;;
		vendor/etc/vintf/manifest/manifest_media_c2_V1_2_default.xml)
			sed -i 's/1.1/1.2/' "$2"
			;;
		vendor/lib*/libaiselector.so | vendor/lib*/libdpframework.so | vendor/lib*/libmtk_drvb.so | \
		vendor/lib*/libnir_neon_driver.so | vendor/lib*/libpq_prot.so)
			symlink_fixup "${1}" "${2}"
			;;
		vendor/lib*/hw/android.hardware.camera.provider@2.6-impl-mediatek.so)
			grep -q "libutils.so" "${2}" && \
			"${PATCHELF}" --replace-needed "libutils.so" "libutils-v32.so" "${2}"
			;;
		vendor/lib*/hw/vendor.mediatek.hardware.pq@*-impl.so)
			grep -q "libutils.so" "${2}" && \
			"${PATCHELF}" --replace-needed "libutils.so" "libutils-v32.so" "${2}"
			;;
		vendor/lib*/libmtkcam_stdutils.so)
			grep -q "libutils.so" "${2}" && \
			"${PATCHELF}" --replace-needed "libutils.so" "libutils-v32.so" "${2}"
			;;
		vendor/lib*/libwvhidl.so | vendor/lib*/mediadrm/libwvdrmengine.so)
			grep -q "libprotobuf-cpp-lite-3.9.1.so" "${2}" && \
			"${PATCHELF}" --replace-needed "libprotobuf-cpp-lite-3.9.1.so" "libprotobuf-cpp-full-3.9.1.so" "${2}"
			;;
	esac
}


function blob_fixup_dry() {
    blob_fixup "$1" ""
}

function prepare_firmware() {
    if [ "${SRC}" != "adb" ]; then
        local STAR="${ANDROID_ROOT}"/lineage/scripts/motorola/star.sh
        for IMAGE in bootloader radio; do
            if [ -f "${SRC}/${IMAGE}.img" ]; then
                echo "Extracting Motorola star image ${SRC}/${IMAGE}.img"
                sh "${STAR}" "${SRC}/${IMAGE}.img" "${SRC}"
            fi
        done
    fi
}

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

if [ -z "${ONLY_FIRMWARE}" ]; then
    extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"

    generate_prop_list_from_image "product.img" "${MY_DIR}/proprietary-files-carriersettings.txt" CARRIER_SKIP_FILES carriersettings
    extract "${MY_DIR}/proprietary-files-carriersettings.txt" "${SRC}" "${KANG}" --section "${SECTION}"

    extract_carriersettings
fi

if [ -z "${SECTION}" ]; then
    extract_firmware "${MY_DIR}/proprietary-firmware.txt" "${SRC}"
fi

"${MY_DIR}/setup-makefiles.sh"
