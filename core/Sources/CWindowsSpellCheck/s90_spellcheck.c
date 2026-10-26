#include "s90_spellcheck.h"

#ifdef _WIN32
#define COBJMACROS
#include <windows.h>
#include <objbase.h>
#include <spellcheck.h>
#include <string.h>

static ISpellChecker *checker = NULL;

/// 長さを決めた UTF-16 を，終わりに 0 を置いた文字列に写す(呼んだ側が CoTaskMemFree で放す)
static LPWSTR copy_terminated(const uint16_t *text, int32_t length) {
    if (text == NULL || length <= 0) return NULL;
    LPWSTR copy = (LPWSTR)CoTaskMemAlloc(((SIZE_T)length + 1) * sizeof(WCHAR));
    if (copy == NULL) return NULL;
    memcpy(copy, text, (SIZE_T)length * sizeof(WCHAR));
    copy[length] = 0;
    return copy;
}

int32_t s90_spell_open(const uint16_t *language) {
    if (checker != NULL) return 0;
    HRESULT result = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(result) && result != RPC_E_CHANGED_MODE) return -1;
    ISpellCheckerFactory *factory = NULL;
    if (FAILED(CoCreateInstance(&CLSID_SpellCheckerFactory, NULL, CLSCTX_INPROC_SERVER, &IID_ISpellCheckerFactory, (void **)&factory))) return -2;
    BOOL supported = FALSE;
    LPCWSTR tag = (LPCWSTR)language;
    if (FAILED(ISpellCheckerFactory_IsSupported(factory, tag, &supported)) || !supported) {
        ISpellCheckerFactory_Release(factory);
        return -3;
    }
    result = ISpellCheckerFactory_CreateSpellChecker(factory, tag, &checker);
    ISpellCheckerFactory_Release(factory);
    return SUCCEEDED(result) ? 0 : -4;
}

int32_t s90_spell_is_word(const uint16_t *word, int32_t length) {
    if (checker == NULL) return -1;
    LPWSTR text = copy_terminated(word, length);
    if (text == NULL) return -1;
    IEnumSpellingError *errors = NULL;
    HRESULT result = ISpellChecker_Check(checker, text, &errors);
    CoTaskMemFree(text);
    if (FAILED(result) || errors == NULL) return -1;
    ISpellingError *error = NULL;
    // 誤りが 1 つも無ければ英単語(S_FALSE は「もう無い」)
    result = IEnumSpellingError_Next(errors, &error);
    if (result == S_OK && error != NULL) {
        ISpellingError_Release(error);
        IEnumSpellingError_Release(errors);
        return 0;
    }
    IEnumSpellingError_Release(errors);
    return result == S_FALSE ? 1 : -1;
}

int32_t s90_spell_suggestions(const uint16_t *word, int32_t length, uint16_t *buffer, int32_t capacity, int32_t maximum) {
    if (checker == NULL || buffer == NULL || capacity <= 0) return -1;
    LPWSTR text = copy_terminated(word, length);
    if (text == NULL) return -1;
    IEnumString *suggestions = NULL;
    HRESULT result = ISpellChecker_Suggest(checker, text, &suggestions);
    CoTaskMemFree(text);
    if (FAILED(result) || suggestions == NULL) return -1;
    int32_t written = 0;
    int32_t count = 0;
    LPOLESTR suggestion = NULL;
    while (count < maximum && IEnumString_Next(suggestions, 1, &suggestion, NULL) == S_OK && suggestion != NULL) {
        int32_t size = (int32_t)wcslen(suggestion);
        // 区切りの改行を含めて入らなければやめる
        if (written + size + (written > 0 ? 1 : 0) > capacity) {
            CoTaskMemFree(suggestion);
            break;
        }
        if (written > 0) buffer[written++] = L'\n';
        memcpy(buffer + written, suggestion, (SIZE_T)size * sizeof(WCHAR));
        written += size;
        count += 1;
        CoTaskMemFree(suggestion);
        suggestion = NULL;
    }
    IEnumString_Release(suggestions);
    return written;
}

void s90_spell_close(void) {
    if (checker != NULL) {
        ISpellChecker_Release(checker);
        checker = NULL;
    }
}

#else

int32_t s90_spell_open(const uint16_t *language) { (void)language; return -1; }
int32_t s90_spell_is_word(const uint16_t *word, int32_t length) { (void)word; (void)length; return -1; }
int32_t s90_spell_suggestions(const uint16_t *word, int32_t length, uint16_t *buffer, int32_t capacity, int32_t maximum) {
    (void)word; (void)length; (void)buffer; (void)capacity; (void)maximum;
    return -1;
}
void s90_spell_close(void) {}

#endif
