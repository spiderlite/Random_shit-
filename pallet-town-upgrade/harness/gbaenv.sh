# source this: exports symbol addresses for gba's pos/step commands
_nm() { arm-none-eabi-nm "$(dirname "${BASH_SOURCE[0]}")/../pokefirered/pokefirered.elf" | awk -v s="$1" '$3==s{print $1}'; }
export GBA_OBJECT_EVENTS=$(_nm gObjectEvents) GBA_PLAYER_AVATAR=$(_nm gPlayerAvatar) GBA_SAVEBLOCK1_PTR=$(_nm gSaveBlock1Ptr)
