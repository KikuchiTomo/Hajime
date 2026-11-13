#include "hajime_hash.h"

#ifdef _WIN32
#include <windows.h>
#include <bcrypt.h>

/// SHA-256 のアルゴリズムのハンドル．開くのに時間がかかるので，最初に使うときに 1 度だけ開いて使い回す(BCrypt のハンドルはスレッドをまたいで使える)
static INIT_ONCE provider_once = INIT_ONCE_STATIC_INIT;
static BCRYPT_ALG_HANDLE provider = NULL;

static BOOL CALLBACK open_provider(PINIT_ONCE once, PVOID parameter, PVOID *context) {
    (void)once;
    (void)parameter;
    (void)context;
    if (!BCRYPT_SUCCESS(BCryptOpenAlgorithmProvider(&provider, BCRYPT_SHA256_ALGORITHM, NULL, 0))) provider = NULL;
    return TRUE;
}

hajime_sha256 *hajime_sha256_begin(void) {
    if (!InitOnceExecuteOnce(&provider_once, open_provider, NULL, NULL) || provider == NULL) return NULL;
    BCRYPT_HASH_HANDLE hash = NULL;
    // 状態を置く場所は BCrypt に任せる(Windows 7 以降)
    if (!BCRYPT_SUCCESS(BCryptCreateHash(provider, &hash, NULL, 0, NULL, 0, 0))) return NULL;
    return (hajime_sha256 *)hash;
}

int32_t hajime_sha256_update(hajime_sha256 *state, const uint8_t *bytes, size_t count) {
    if (state == NULL) return -1;
    if (count == 0) return 0;
    if (bytes == NULL) return -1;
    // BCryptHashData は ULONG(32 ビット)の長さしか受け取らないので，区切って渡す
    while (count > 0) {
        ULONG piece = count > 0x40000000u ? 0x40000000u : (ULONG)count;
        if (!BCRYPT_SUCCESS(BCryptHashData((BCRYPT_HASH_HANDLE)state, (PUCHAR)bytes, piece, 0))) return -2;
        bytes += piece;
        count -= piece;
    }
    return 0;
}

int32_t hajime_sha256_finish(hajime_sha256 *state, uint8_t *digest) {
    if (state == NULL) return -1;
    NTSTATUS status = digest == NULL ? (NTSTATUS)-1 : BCryptFinishHash((BCRYPT_HASH_HANDLE)state, (PUCHAR)digest, 32, 0);
    BCryptDestroyHash((BCRYPT_HASH_HANDLE)state);
    return BCRYPT_SUCCESS(status) ? 0 : -2;
}

void hajime_sha256_discard(hajime_sha256 *state) {
    if (state != NULL) BCryptDestroyHash((BCRYPT_HASH_HANDLE)state);
}

int32_t hajime_file_stamp_of(const uint16_t *path, hajime_file_stamp *stamp) {
    if (path == NULL || stamp == NULL) return -1;
    // 属性を読むだけなので中身の読み取りは求めない．ほかのプロセスが開いていても読めるよう，共有はすべて許す
    HANDLE file = CreateFileW((LPCWSTR)path, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
                              FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return -2;
    BY_HANDLE_FILE_INFORMATION information;
    BOOL read = GetFileInformationByHandle(file, &information);
    CloseHandle(file);
    if (!read || (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) return -3;
    stamp->size = ((uint64_t)information.nFileSizeHigh << 32) | information.nFileSizeLow;
    stamp->modified = (int64_t)(((uint64_t)information.ftLastWriteTime.dwHighDateTime << 32) | information.ftLastWriteTime.dwLowDateTime);
    stamp->volume = information.dwVolumeSerialNumber;
    stamp->file = ((uint64_t)information.nFileIndexHigh << 32) | information.nFileIndexLow;
    return 0;
}

int32_t hajime_directory_stamps(const uint16_t *directory, void *context, hajime_file_stamp_visitor visitor) {
    if (directory == NULL || visitor == NULL) return -1;
    HANDLE handle = CreateFileW((LPCWSTR)directory, FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    if (handle == INVALID_HANDLE_VALUE) return -2;
    BY_HANDLE_FILE_INFORMATION information;
    if (!GetFileInformationByHandle(handle, &information) || (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
        CloseHandle(handle);
        return -3;
    }
    // 8 バイトにそろえた置き場所(FILE_ID_BOTH_DIR_INFO は LARGE_INTEGER を含む)
    static const size_t capacity = 64 * 1024;
    LONGLONG *buffer = (LONGLONG *)HeapAlloc(GetProcessHeap(), 0, capacity);
    if (buffer == NULL) {
        CloseHandle(handle);
        return -4;
    }
    int32_t result = 0;
    FILE_INFO_BY_HANDLE_CLASS kind = FileIdBothDirectoryRestartInfo;
    for (;;) {
        if (!GetFileInformationByHandleEx(handle, kind, buffer, (DWORD)capacity)) {
            if (GetLastError() != ERROR_NO_MORE_FILES) result = -5;
            break;
        }
        kind = FileIdBothDirectoryInfo;
        const unsigned char *cursor = (const unsigned char *)buffer;
        for (;;) {
            const FILE_ID_BOTH_DIR_INFO *entry = (const FILE_ID_BOTH_DIR_INFO *)cursor;
            if ((entry->FileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) == 0) {
                hajime_file_stamp stamp;
                stamp.size = (uint64_t)entry->EndOfFile.QuadPart;
                stamp.modified = entry->LastWriteTime.QuadPart;
                stamp.volume = information.dwVolumeSerialNumber;
                stamp.file = (uint64_t)entry->FileId.QuadPart;
                visitor(context, (const uint16_t *)entry->FileName, (uint32_t)(entry->FileNameLength / sizeof(WCHAR)), &stamp);
            }
            if (entry->NextEntryOffset == 0) break;
            cursor += entry->NextEntryOffset;
        }
    }
    HeapFree(GetProcessHeap(), 0, buffer);
    CloseHandle(handle);
    return result;
}

#else

hajime_sha256 *hajime_sha256_begin(void) { return NULL; }

int32_t hajime_sha256_update(hajime_sha256 *state, const uint8_t *bytes, size_t count) {
    (void)state;
    (void)bytes;
    (void)count;
    return -1;
}

int32_t hajime_sha256_finish(hajime_sha256 *state, uint8_t *digest) {
    (void)state;
    (void)digest;
    return -1;
}

void hajime_sha256_discard(hajime_sha256 *state) { (void)state; }

int32_t hajime_file_stamp_of(const uint16_t *path, hajime_file_stamp *stamp) {
    (void)path;
    (void)stamp;
    return -1;
}

int32_t hajime_directory_stamps(const uint16_t *directory, void *context, hajime_file_stamp_visitor visitor) {
    (void)directory;
    (void)context;
    (void)visitor;
    return -1;
}

#endif
