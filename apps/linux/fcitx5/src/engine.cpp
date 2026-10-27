#include "engine.h"

#include <ctime>
#include <optional>
#include <utility>

#include <fcitx-utils/key.h>
#include <fcitx-utils/keysym.h>
#include <fcitx-utils/log.h>
#include <fcitx/candidatelist.h>
#include <fcitx/inputpanel.h>
#include <fcitx/text.h>
#include <fcitx/userinterface.h>

#ifndef S90_ENGINE_PATH
#error "S90_ENGINE_PATH(エンジンの実行ファイルの場所)を CMake で渡してください"
#endif

namespace s90 {
namespace {

struct KeyCode {
    uint32_t kind;
    std::string text;
    uint32_t number = 0;
    bool keypad = false;
};

bool isKeypad(fcitx::KeySym sym) { return sym >= FcitxKey_KP_Space && sym <= FcitxKey_KP_9; }

// Fcitx 5 のキーを，エンジンのキー(s90_bridge.h の S90KeyKind)にする．エンジンが扱わないキー(修飾キーだけなど)は nullopt
std::optional<KeyCode> keyCode(const fcitx::Key &key) {
    const fcitx::KeySym sym = key.sym();
    switch (sym) {
    case FcitxKey_space:
    case FcitxKey_KP_Space:
        return KeyCode{S90_KEY_SPACE, {}};
    case FcitxKey_Return:
    case FcitxKey_KP_Enter:
        return KeyCode{S90_KEY_ENTER, {}};
    case FcitxKey_BackSpace:
        return KeyCode{S90_KEY_BACKSPACE, {}};
    case FcitxKey_Delete:
    case FcitxKey_KP_Delete:
        return KeyCode{S90_KEY_DELETE, {}};
    case FcitxKey_Escape:
        return KeyCode{S90_KEY_ESCAPE, {}};
    case FcitxKey_Tab:
    case FcitxKey_ISO_Left_Tab:
        return KeyCode{S90_KEY_TAB, {}};
    case FcitxKey_Up:
    case FcitxKey_KP_Up:
        return KeyCode{S90_KEY_UP, {}};
    case FcitxKey_Down:
    case FcitxKey_KP_Down:
        return KeyCode{S90_KEY_DOWN, {}};
    case FcitxKey_Left:
    case FcitxKey_KP_Left:
        return KeyCode{S90_KEY_LEFT, {}};
    case FcitxKey_Right:
    case FcitxKey_KP_Right:
        return KeyCode{S90_KEY_RIGHT, {}};
    case FcitxKey_Home:
    case FcitxKey_KP_Home:
        return KeyCode{S90_KEY_HOME, {}};
    case FcitxKey_End:
    case FcitxKey_KP_End:
        return KeyCode{S90_KEY_END, {}};
    case FcitxKey_Page_Up:
    case FcitxKey_KP_Page_Up:
        return KeyCode{S90_KEY_PAGE_UP, {}};
    case FcitxKey_Page_Down:
    case FcitxKey_KP_Page_Down:
        return KeyCode{S90_KEY_PAGE_DOWN, {}};
    case FcitxKey_Eisu_toggle:
    case FcitxKey_Eisu_Shift:
        return KeyCode{S90_KEY_EISU, {}};
    case FcitxKey_Hiragana_Katakana:
    case FcitxKey_Hiragana:
    case FcitxKey_Katakana:
        return KeyCode{S90_KEY_KANA, {}};
    case FcitxKey_yen:
        return KeyCode{S90_KEY_YEN, {}};
    case FcitxKey_Zenkaku_Hankaku:
    case FcitxKey_Zenkaku:
    case FcitxKey_Hankaku:
        return KeyCode{S90_KEY_HANKAKU_ZENKAKU, {}};
    case FcitxKey_Henkan_Mode:
        return KeyCode{S90_KEY_HENKAN, {}};
    case FcitxKey_Muhenkan:
        return KeyCode{S90_KEY_MUHENKAN, {}};
    default:
        break;
    }
    if (sym >= FcitxKey_F1 && sym <= FcitxKey_F24) {
        return KeyCode{S90_KEY_FUNCTION, {}, static_cast<uint32_t>(sym - FcitxKey_F1 + 1)};
    }
    std::string text = fcitx::Key::keySymToUTF8(sym);
    if (text.empty()) {
        return std::nullopt;
    }
    return KeyCode{S90_KEY_CHARACTER, std::move(text), 0, isKeypad(sym)};
}

uint32_t modifiers(const fcitx::Key &key) {
    uint32_t result = 0;
    const auto states = key.states();
    if (states.test(fcitx::KeyState::Shift)) {
        result |= S90_MODIFIER_SHIFT;
    }
    if (states.test(fcitx::KeyState::Ctrl)) {
        result |= S90_MODIFIER_CONTROL;
    }
    if (states.test(fcitx::KeyState::Alt)) {
        result |= S90_MODIFIER_ALT;
    }
    return result;
}

// パスワードなどの欄では，エンジンは前の文字列を読まず，学習もしない
int isSecure(fcitx::InputContext *inputContext) {
    const auto flags = inputContext->capabilityFlags();
    return flags.test(fcitx::CapabilityFlag::Password) || flags.test(fcitx::CapabilityFlag::Sensitive) ? 1 : 0;
}

fcitx::TextFormatFlags format(uint32_t style) {
    switch (style) {
    case S90_STYLE_FOCUSED:
        return {fcitx::TextFormatFlag::Underline, fcitx::TextFormatFlag::HighLight};
    case S90_STYLE_CORRECTION:
        return {fcitx::TextFormatFlag::Underline, fcitx::TextFormatFlag::Bold};
    default:
        return fcitx::TextFormatFlag::Underline;
    }
}

// 候補はキーで選ぶ(エンジンが選んだ位置を受け取って出す)．マウスで押したときの選び方はまだ無い(ADR 0012)
class Candidate : public fcitx::CandidateWord {
public:
    explicit Candidate(const std::string &text) : fcitx::CandidateWord(fcitx::Text(text)) {}
    void select(fcitx::InputContext *) const override {}
};

uint64_t after(uint32_t milliseconds) {
    return fcitx::now(CLOCK_MONOTONIC) + static_cast<uint64_t>(milliseconds) * 1000;
}

} // namespace

Engine::Engine(fcitx::Instance *instance) : instance_(instance) {
    bridge_ = s90_bridge_new(S90_ENGINE_PATH);
    if (bridge_ == nullptr) {
        FCITX_ERROR() << "s90.tokyo IME: エンジンへの橋渡しを作れません．キーはそのままアプリに渡します";
        return;
    }
    const int fd = s90_bridge_notify_fd(bridge_);
    if (fd >= 0) {
        panelEvent_ = instance_->eventLoop().addIOEvent(
            fd, fcitx::IOEventFlag::In, [this](fcitx::EventSourceIO *, int, fcitx::IOEventFlags) {
                if (auto *inputContext = target_.get()) {
                    showPanel(inputContext);
                } else {
                    s90_bridge_load_panel(bridge_);
                }
                return true;
            });
    }
}

Engine::~Engine() {
    panelEvent_.reset();
    wakeEvent_.reset();
    s90_bridge_free(bridge_);
}

void Engine::keyEvent(const fcitx::InputMethodEntry &, fcitx::KeyEvent &keyEvent) {
    if (bridge_ == nullptr || keyEvent.isRelease()) {
        return;
    }
    const auto code = keyCode(keyEvent.key());
    if (!code) {
        return;
    }
    auto *inputContext = keyEvent.inputContext();
    target_ = inputContext->watch();
    const std::string program = inputContext->program();
    const int handled = s90_bridge_key(bridge_, code->kind, code->text.empty() ? nullptr : code->text.c_str(), code->number,
                                       modifiers(keyEvent.key()), code->keypad ? 1 : 0, program.c_str(), isSecure(inputContext));
    render(inputContext);
    scheduleWake(inputContext);
    if (handled != 0) {
        keyEvent.filterAndAccept();
    }
}

void Engine::activate(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) {
    target_ = event.inputContext()->watch();
}

void Engine::deactivate(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) {
    finish(event.inputContext());
}

void Engine::reset(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) {
    finish(event.inputContext());
}

// 入力先から外れたら，組み立て中の文字の扱いをエンジンに任せ(確定するなら確定する)，候補を消す
void Engine::finish(fcitx::InputContext *inputContext) {
    if (bridge_ == nullptr) {
        return;
    }
    wakeEvent_.reset();
    s90_bridge_deactivate(bridge_);
    render(inputContext);
    inputContext->inputPanel().reset();
    inputContext->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
}

void Engine::render(fcitx::InputContext *inputContext) {
    const char *commit = s90_bridge_commit(bridge_);
    if (commit != nullptr && commit[0] != '\0') {
        inputContext->commitString(commit);
    }
    fcitx::Text preedit;
    const size_t count = s90_bridge_preedit_count(bridge_);
    for (size_t index = 0; index < count; ++index) {
        uint32_t style = S90_STYLE_READING;
        const char *text = s90_bridge_preedit_text(bridge_, index, &style);
        if (text != nullptr) {
            preedit.append(text, format(style));
        }
    }
    preedit.setCursor(static_cast<int>(preedit.textLength()));
    auto &panel = inputContext->inputPanel();
    if (inputContext->capabilityFlags().test(fcitx::CapabilityFlag::Preedit)) {
        panel.setClientPreedit(preedit);
    } else {
        panel.setPreedit(preedit);
    }
    inputContext->updatePreedit();
    inputContext->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
}

void Engine::showPanel(fcitx::InputContext *inputContext) {
    s90_bridge_load_panel(bridge_);
    auto &panel = inputContext->inputPanel();
    const size_t count = s90_bridge_candidate_count(bridge_);
    if (count == 0) {
        panel.setCandidateList(nullptr);
        panel.setAuxUp(fcitx::Text());
        panel.setAuxDown(fcitx::Text());
    } else {
        // エンジンが 1 ページ分の候補を送るので，すべてを 1 ページに出す
        auto list = std::make_unique<fcitx::CommonCandidateList>();
        list->setPageSize(static_cast<int>(count));
        list->setLayoutHint(fcitx::CandidateLayoutHint::Vertical);
        for (size_t index = 0; index < count; ++index) {
            const char *text = s90_bridge_candidate(bridge_, index);
            list->append<Candidate>(text != nullptr ? text : "");
        }
        const int32_t selected = s90_bridge_selected(bridge_);
        if (selected >= 0 && static_cast<size_t>(selected) < count) {
            list->setGlobalCursorIndex(selected);
        }
        panel.setCandidateList(std::move(list));
        const char *note = s90_bridge_note(bridge_);
        panel.setAuxUp(fcitx::Text(note != nullptr ? note : ""));
        const char *hints = s90_bridge_hints(bridge_);
        panel.setAuxDown(fcitx::Text(hints != nullptr ? hints : ""));
    }
    inputContext->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
}

void Engine::scheduleWake(fcitx::InputContext *inputContext) {
    const uint32_t milliseconds = s90_bridge_wake_after(bridge_);
    if (milliseconds == 0) {
        wakeEvent_.reset();
        return;
    }
    target_ = inputContext->watch();
    // 時計の事象の中で事象そのものを作り直すと，動いている事象を消してしまう．
    // 続けて wake が要るときは，同じ事象の時刻を進めて使い回す
    wakeEvent_ = instance_->eventLoop().addTimeEvent(
        CLOCK_MONOTONIC, after(milliseconds), 0, [this](fcitx::EventSourceTime *source, uint64_t) {
            auto *inputContext = target_.get();
            if (inputContext == nullptr) {
                source->setEnabled(false);
                return true;
            }
            const std::string program = inputContext->program();
            s90_bridge_wake(bridge_, program.c_str(), isSecure(inputContext));
            render(inputContext);
            const uint32_t next = s90_bridge_wake_after(bridge_);
            if (next == 0) {
                source->setEnabled(false);
            } else {
                source->setTime(after(next));
                source->setOneShot();
            }
            return true;
        });
}

fcitx::AddonInstance *EngineFactory::create(fcitx::AddonManager *manager) { return new Engine(manager->instance()); }

} // namespace s90

FCITX_ADDON_FACTORY(s90::EngineFactory);
