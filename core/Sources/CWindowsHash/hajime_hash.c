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

#endif
