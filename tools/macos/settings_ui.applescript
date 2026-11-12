-- 開発版(Hajime Debug)の設定の画面を System Events で操作する．tools/macos/check_settings_ui.py から呼ぶ．
-- 部品は「まとまりの番号(ページの中の何番目の group か)・役割・名前・同じ名前の何番目か」で指す．
-- 「既定に戻す」のボタンが出入りすると要素の番号がずれるので，番号では指さない
--
-- osascript settings_ui.applescript pages                         左の一覧のページの名前
-- osascript settings_ui.applescript select <ページ>               ページを開く
-- osascript settings_ui.applescript controls                      開いているページの部品(1 行に 1 つ，タブ区切り)
-- osascript settings_ui.applescript states                        部品の使えるかだけ(値と「既定に戻す」を読まないので速い)
-- osascript settings_ui.applescript press <名前>                   開いているページの名前のボタンを押す
-- osascript settings_ui.applescript press-last                    開いているページのいちばん下のボタンを押す(名前の読めないボタン)
-- osascript settings_ui.applescript act <まとまり> <役割> <名前> <番目> <操作> [回数]
--     操作: click・increment・decrement・restore(すぐ後ろの「既定に戻す」を押す)・menu(選択肢の名前)・choose(選択肢を選ぶ．回数の代わりに選択肢の名前)

property processName : "Hajime Debug"
property restoreHelp : "既定に戻す"
property controlRoles : {"AXCheckBox", "AXPopUpButton", "AXIncrementor", "AXSlider"}
-- 表の中の部品(行ごとの選択肢やスイッチ)は一覧の編集なので，ここでは操作しない
property skippedRoles : {"AXTable", "AXOutline", "AXRow", "AXScrollArea"}

on run argv
	set command to item 1 of argv
	if command is "pages" then return my pageNames()
	if command is "select" then return my selectPage(item 2 of argv)
	if command is "controls" then return my listControls(true)
	if command is "states" then return my listControls(false)
	if command is "press" then return my press(item 2 of argv)
	if command is "press-last" then return my pressLast()
	if command is "act" then
		set extra to ""
		if (count of argv) ≥ 7 then set extra to item 7 of argv
		return my act(item 2 of argv as integer, item 3 of argv, item 4 of argv, item 5 of argv as integer, item 6 of argv, extra)
	end if
	error "知らない命令: " & command
end run

-- 設定の画面の窓(初期設定の窓などを除く)
on settingsWindow()
	tell application "System Events"
		tell my targetProcess()
			repeat with w in windows
				if exists splitter group 1 of group 1 of w then return contents of w
			end repeat
		end tell
	end tell
	error "設定の画面が見つかりません"
end settingsWindow

-- 操作するプロセス．HAJIME_UI_PID があればその番号のプロセス(ほかの人が同時に開発版を動かしていても取り違えない)
on targetProcess()
	set pidText to system attribute "HAJIME_UI_PID"
	tell application "System Events"
		if pidText is "" then return process processName
		return first process whose unix id is (pidText as integer)
	end tell
end targetProcess

on sidebar()
	tell application "System Events" to return outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of (my settingsWindow())
end sidebar

on detail()
	tell application "System Events" to return scroll area 1 of group 1 of group 3 of splitter group 1 of group 1 of (my settingsWindow())
end detail

on pageNames()
	set names to {}
	tell application "System Events"
		repeat with r in rows of (my sidebar())
			try
				set end of names to value of static text 1 of UI element 1 of r
			end try
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	return names as text
end pageNames

on selectPage(pageName)
	tell application "System Events"
		repeat with r in rows of (my sidebar())
			try
				if (value of static text 1 of UI element 1 of r) is pageName then
					set selected of r to true
					repeat 40 times
						if name of (my settingsWindow()) is pageName then return pageName
						delay 0.25
					end repeat
					error "ページが開きません: " & pageName
				end if
			end try
		end repeat
	end tell
	error "ページがありません: " & pageName
end selectPage

-- 開いているページのまとまりごとの部品．「まとまり<TAB>役割<TAB>名前<TAB>番目<TAB>使えるか<TAB>値<TAB>既定に戻すがあるか」
on listControls(withDetails)
	set found to {}
	tell application "System Events"
		set groupIndex to 0
		repeat with g in (groups of (my detail()))
			set groupIndex to groupIndex + 1
			set seen to {}
			set elements to my flatContents(g)
			set elementCount to count of elements
			repeat with i from 1 to elementCount
				set e to item i of elements
				set r to ""
				try
					set r to role of e
				end try
				if r is in controlRoles then
					set n to my nameOf(e)
					set k to my occurrence(seen, r & ":" & my withoutDigits(n))
					set end of seen to r & ":" & my withoutDigits(n)
					set v to ""
					set restorable to "0"
					if withDetails then
						try
							set v to value of e as text
						end try
						if my restoreButtonAfter(elements, i) is not missing value then set restorable to "1"
					end if
					set end of found to (groupIndex as text) & tab & r & tab & n & tab & (k as text) & tab & ((enabled of e) as text) & tab & v & tab & restorable
				end if
			end repeat
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	return found as text
end listControls

-- まとまりの中の要素を，表の中を除いて並び順に集める
on flatContents(parentElement)
	set found to {}
	tell application "System Events"
		repeat with e in (UI elements of parentElement)
			set e to contents of e
			set end of found to e
			set r to ""
			try
				set r to role of e
			end try
			if r is not in controlRoles and r is not in skippedRoles then
				set found to found & my flatContents(e)
			end if
		end repeat
	end tell
	return found
end flatContents

on nameOf(e)
	tell application "System Events"
		try
			set n to name of e
			if n is not missing value then return n as text
		end try
		try
			set n to description of e
			if n is not missing value then return n as text
		end try
	end tell
	return ""
end nameOf

on withoutDigits(textValue)
	set result_ to ""
	repeat with c in (characters of textValue)
		if c is not in {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "."} then set result_ to result_ & c
	end repeat
	return result_
end withoutDigits

on occurrence(seen, key)
	set k to 1
	repeat with s in seen
		if (contents of s) is key then set k to k + 1
	end repeat
	return k
end occurrence

-- i 番目の部品のすぐ後ろ(次の部品より前)にある「既定に戻す」のボタン．無ければ missing value
on restoreButtonAfter(elements, i)
	tell application "System Events"
		repeat with j from (i + 1) to (count of elements)
			set e to item j of elements
			set r to ""
			try
				set r to role of e
			end try
			if r is in controlRoles then return missing value
			if r is "AXButton" then
				try
					if (value of attribute "AXHelp" of e) is restoreHelp then return e
				end try
			end if
		end repeat
	end tell
	return missing value
end restoreButtonAfter

on press(buttonName)
	tell application "System Events"
		-- まとまりに入らないボタン(1 つだけの Section の中のボタン)もあるので，ページ全体から探す
		set elements to entire contents of (my detail())
		repeat with e in elements
			try
				if role of e is "AXButton" and (my nameOf(e)) is buttonName then
					click e
					return buttonName
				end if
			end try
		end repeat
	end tell
	error "ボタンが見つかりません: " & buttonName
end press

on findControl(groupIndex, wantedRole, wantedName, wantedOccurrence)
	tell application "System Events"
		set elements to my flatContents(group groupIndex of (my detail()))
		set k to 0
		repeat with e in elements
			set r to ""
			try
				set r to role of e
			end try
			if r is wantedRole and my withoutDigits(my nameOf(e)) is my withoutDigits(wantedName) then
				set k to k + 1
				if k is wantedOccurrence then return contents of e
			end if
		end repeat
	end tell
	error "部品が見つかりません: " & wantedName
end findControl

-- 開いているページのいちばん下のまとまりの，最後のボタンを押す．SwiftUI のボタンの名前は System Events から読めない(AXAttributedDescription にだけある)ので，位置で指す
on pressLast()
	tell application "System Events"
		set g to last group of (my detail())
		click last button of g
	end tell
	return "ok"
end pressLast

on act(groupIndex, wantedRole, wantedName, wantedOccurrence, operation, extra)
	if (operation is "increment" or operation is "decrement") and extra is not "" then
		-- 何段も動かす．名前に値が入る部品は 1 段動かすと前の参照が使えなくなるので，使えなくなったら探し直す
		set actionName to "AXIncrement"
		if operation is "decrement" then set actionName to "AXDecrement"
		set e to my findControl(groupIndex, wantedRole, wantedName, wantedOccurrence)
		repeat (extra as integer) times
			try
				tell application "System Events" to perform action actionName of e
			on error
				set e to my findControl(groupIndex, wantedRole, wantedName, wantedOccurrence)
				tell application "System Events" to perform action actionName of e
			end try
		end repeat
		return ""
	end if
	tell application "System Events"
		set g to group groupIndex of (my detail())
		set elements to my flatContents(g)
		set k to 0
		repeat with i from 1 to (count of elements)
			set e to item i of elements
			set r to ""
			try
				set r to role of e
			end try
			-- 名前に今の値を含む部品(「候補の文字サイズ: 15」)は，値を変えると名前が変わるので，数字を除いて比べる
			if r is wantedRole and my withoutDigits(my nameOf(e)) is my withoutDigits(wantedName) then
				set k to k + 1
				if k is wantedOccurrence then return my operate(e, elements, i, operation, extra)
			end if
		end repeat
	end tell
	error "部品が見つかりません: " & wantedName
end act

on operate(e, elements, i, operation, extra)
	tell application "System Events"
		if operation is "click" then
			click e
		else if operation is "increment" or operation is "decrement" then
			set count_ to 1
			if extra is not "" then set count_ to extra as integer
			set actionName to "AXIncrement"
			if operation is "decrement" then set actionName to "AXDecrement"
			repeat count_ times
				perform action actionName of e
			end repeat
		else if operation is "restore" then
			set b to my restoreButtonAfter(elements, i)
			if b is missing value then return "none"
			click b
		else if operation is "menu" then
			click e
			delay 0.3
			set names to name of every menu item of menu 1 of e
			-- 開いた選択肢の一覧は取り消して閉じる．選んでいる値を選び直すと，同じ値でも書き直す画面がある(同期の範囲)
			perform action "AXCancel" of menu 1 of e
			set AppleScript's text item delimiters to linefeed
			return names as text
		else if operation is "choose" then
			click e
			delay 0.3
			click menu item extra of menu 1 of e
		else
			error "知らない操作: " & operation
		end if
		try
			return value of e as text
		end try
	end tell
	return ""
end operate
