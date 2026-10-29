// はじめの Fcitx 5 のアドオン．キーを Rust の橋渡し(bridge/)に渡し，返ってきた入力中の文字・確定・候補の一覧を Fcitx 5 に出す．
// 入力の状態・候補・補正はすべてエンジン(hajime-engine-host)が決める(docs/dev/adr/0012-linux.md)
#ifndef HAJIME_FCITX5_ENGINE_H
#define HAJIME_FCITX5_ENGINE_H

#include <memory>
#include <string>

#include <fcitx-utils/event.h>
#include <fcitx-utils/trackableobject.h>
#include <fcitx/addonfactory.h>
#include <fcitx/addonmanager.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputmethodengine.h>
#include <fcitx/instance.h>

#include "hajime_bridge.h"

namespace hajime {

class Engine : public fcitx::InputMethodEngine {
public:
    explicit Engine(fcitx::Instance *instance);
    ~Engine() override;

    void keyEvent(const fcitx::InputMethodEntry &entry, fcitx::KeyEvent &keyEvent) override;
    void activate(const fcitx::InputMethodEntry &entry, fcitx::InputContextEvent &event) override;
    void deactivate(const fcitx::InputMethodEntry &entry, fcitx::InputContextEvent &event) override;
    void reset(const fcitx::InputMethodEntry &entry, fcitx::InputContextEvent &event) override;

private:
    // 直前の key・wake・deactivate の結果(確定と入力中の文字)を出す
    void render(fcitx::InputContext *inputContext);
    // 候補の一覧を出し直す
    void showPanel(fcitx::InputContext *inputContext);
    // エンジンが求めた時間のあとに wake を送る
    void scheduleWake(fcitx::InputContext *inputContext);
    void finish(fcitx::InputContext *inputContext);

    fcitx::Instance *instance_;
    HajimeBridge *bridge_ = nullptr;
    // 候補の一覧と wake の結果を出す先(最後にキーを受け取った入力欄)
    fcitx::TrackableObjectReference<fcitx::InputContext> target_;
    std::unique_ptr<fcitx::EventSourceIO> panelEvent_;
    std::unique_ptr<fcitx::EventSourceTime> wakeEvent_;
};

class EngineFactory : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override;
};

} // namespace hajime

#endif
