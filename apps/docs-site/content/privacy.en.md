---
title: Privacy Policy and Disclaimer
description: How Hajime IME handles user information, and the matters for which the developer assumes no liability
url: /privacy/en/
---

This is an English translation of the [Japanese original](privacy.md), provided for reference. If there is any discrepancy between the two, the Japanese original prevails.

This Privacy Policy and Disclaimer (the "Terms") sets out how user information is handled in the Japanese input method Hajime IME, and the matters for which the developer assumes no liability.

## Chapter 1: General Provisions

### Article 1 (Definitions)

In these Terms, the following terms have the meanings set out below.

1. "Software" means the Japanese input method Hajime IME, including its macOS and Windows editions and their source code, executable programs, installers, dictionaries and other data, documentation, and updates.
2. "Developer" means the person who develops and publishes the Software.
3. "User" means any person who obtains, installs, or uses the Software.
4. "License" means the [MIT License](https://github.com/KikuchiTomo/Hajime/blob/main/LICENSE) that applies to the Software.
5. "Third-Party Software" means software, language models, dictionary data, operating system features, and services that are incorporated into or used by the Software and whose rights are held by parties other than the Developer.

### Article 2 (Nature of These Terms)

The Developer distributes the Software free of charge under the License. The conditions for using, copying, modifying, redistributing, and otherwise dealing in the Software are as set out in the License.

## Chapter 2: Privacy Policy

As the basic policy for protecting personal information in the Software, the Developer does not obtain User information beyond what is necessary to check for updates, and does not send what the User types outside the User's device.

### Article 3 (Collection of Information)

1. Except for the information involved in checking for updates under paragraph 4, the Developer does not obtain personal information or any other information of the User through the Software.
2. Except for checking for updates under paragraph 4, the Software does not communicate over a network. The Software never sends the text typed by the User, conversion candidates, learning data, statistics, settings, or the user dictionary outside the User's device.
3. Except for checking for updates under paragraph 4, the Software does not perform external transmission as defined in Article 27-12 of the Telecommunications Business Act of Japan (processing that causes information recorded on the User's device to be sent to a party other than the User), and does not record the User's behavior using cookies or similar technologies.
4. Only when the User selects "更新を確認" (Check for Updates), the Software connects to the website operated by the Developer (https://haji.men) to check for the latest version, and, only when the User chooses to update, to download the release package.
   1. The information sent at this time is limited to the name and version of the Software and the type of operating system (the HTTP User-Agent), and the IP address and other information that is required for and sent with the communication.
   2. The Developer uses the information in the preceding item only to check for updates and to provide release packages, and does not use it to identify Users.
   3. The website is operated using the services of Cloudflare, Inc., and the handling of communication information by Cloudflare, Inc. is governed by its own policies.
   4. The Software does not check for updates or update itself without an action by the User.

### Article 4 (On-Device Processing)

1. The Software performs kana-kanji conversion, typo correction, and all other input-related processing on the User's device.
2. For handwriting input, the Software uses the text recognition feature of macOS in the macOS edition and the handwriting recognition feature of Windows in the Windows edition. Both are performed on the User's device.

### Article 5 (Protection on Each Operating System)

1. In the macOS edition, the program that accepts text input runs under App Sandbox and is not granted permission to connect to a network. Checking for updates and downloading release packages under Article 3, paragraph 4 are performed by a separate program that does not accept text input (Hajime IME Updater), and a downloaded release package is installed after its signature by the Developer and its notarization by Apple are verified.
2. In the Windows edition, the program that accepts text input and the program that performs conversion communicate through a named pipe within the same device, and connections from other devices are not accepted. Checking for updates and downloading release packages under Article 3, paragraph 4 are performed by the settings program, and a downloaded release package is installed after its hash value is verified.

### Article 6 (Information Stored on the Device)

1. To operate, the Software stores the following information on the User's device.
   1. Settings: the values changed in the settings window, and the user dictionary
   2. Learning data: what the Software has learned from confirmed candidates
   3. Statistics: the number of confirmations and corrections (not including the typed text)
   4. Imported dictionaries: the dictionaries added by importing
2. The information in the preceding paragraph is stored in the following locations.

   | Edition | Location |
   |---|---|
   | macOS | `~/Library/Containers/men.haji.inputmethod.Hajime/` |
   | Windows | Settings in `%APPDATA%\haji.men\IME\`, other information in `%LOCALAPPDATA%\haji.men\IME\` |

3. The information in the preceding two paragraphs is used only to keep settings, to improve conversion accuracy, and otherwise to operate the Software. The Developer does not view or use it.
4. The User can delete the learning data and statistics from the settings window, and can stop the recording of statistics.

### Article 7 (Sync and Backup)

1. Only when the User specifies a folder to use for sync, the Software writes settings and dictionaries to that folder.
2. Copying the contents of that folder to other devices is done by the service chosen by the User, such as Dropbox, Google Drive, or iCloud Drive, and the handling of information by that service is governed by the policies of its provider.
3. Files that the Software writes as backups are saved only to the location specified by the User.

### Article 8 (Provision to Third Parties)

The Developer does not obtain User information except as provided in Article 3, paragraph 4, and does not provide the obtained information to third parties (including third parties in foreign countries) or use it jointly with third parties. However, as provided in item 3 of that paragraph, communication information passes through the services of Cloudflare, Inc.

## Chapter 3: Disclaimer

### Article 9 (Disclaimer under the License)

1. The liability of the Developer regarding the Software is governed by the License.
2. The License contains the following provision.

   > THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

3. The articles in this chapter confirm the purport of the provision in the preceding paragraph.

### Article 10 (No Warranty)

1. The Software is distributed as is. The Developer makes no warranty of any kind, express or implied, regarding the Software, including its merchantability, fitness for a particular purpose, accuracy, completeness, usefulness, safety, reliability, continuity, and non-infringement of third-party rights.
2. The Developer does not warrant that the results of kana-kanji conversion, typo correction, prediction, or other processing by the Software are accurate or match the intent of the User.
3. The Developer does not warrant that the Software works correctly on any particular operating system, hardware, or application software, or that the Software is free of bugs, defects, and vulnerabilities.
4. The Developer has no obligation to fix bugs, provide updates, answer inquiries, or otherwise maintain or support the Software.

### Article 11 (Limitation of Liability)

1. The Developer assumes no liability for any damage (including, but not limited to, direct, indirect, incidental, special, and consequential damage and lost profits) incurred by the User or any other person arising out of or in connection with obtaining, installing, using, being unable to use, or uninstalling the Software, regardless of its cause and regardless of whether the claim is based on contract, tort, or any other ground.
2. The damage in the preceding paragraph includes the following.
   1. Loss, corruption, or alteration of typed or saved data, learning data, the user dictionary, and settings
   2. Damage caused by a document with content not intended by the User being created, sent, or published because of an error in the results of conversion or correction
   3. Malfunction, instability, and reduced performance of the operating system or other software
   4. Business interruption, loss of opportunity, and other economic loss
3. The User installs and uses the Software at the User's own discretion and responsibility. Checking the results of conversion and correction is also the User's own responsibility.

### Article 12 (Third-Party Software)

1. Third-Party Software is subject to the licenses and other terms of use set by its respective rights holders. The copyright notices and licenses of the Third-Party Software included in the Software are listed in [THIRD_PARTY_NOTICES.md](https://github.com/KikuchiTomo/Hajime/blob/main/THIRD_PARTY_NOTICES.md).
2. The Developer assumes no liability for the content, quality, or operation of Third-Party Software, or for any damage arising from them.
3. When the User uses a service provided by a third party with the sync feature or other features of the Software, the use of that service is subject to the terms of use between the User and the provider of that service.

### Article 13 (Distribution Channels)

1. The Developer publishes the release packages of the Software only on the [Releases of the repository of the Software on GitHub](https://github.com/KikuchiTomo/Hajime/releases) and on the download page of the website operated by the Developer (https://haji.men/download/).
2. The Developer assumes no liability for the Software obtained from any place other than those in the preceding paragraph, or for the Software modified by anyone other than the Developer.
3. The User can verify that a release package has not been altered by using the hash values in SHA256SUMS.txt, which is published with the release packages.

### Article 14 (Changes to and Discontinuation of Distribution)

The Developer may change the content of the Software or discontinue its distribution without notice to the User. The Developer assumes no liability for any damage incurred by the User or any other person as a result.

## Chapter 4: Miscellaneous

### Article 15 (Inquiries)

Inquiries about these Terms are accepted through the [Issues of the repository of the Software on GitHub](https://github.com/KikuchiTomo/Hajime/issues). However, the Developer has no obligation to answer inquiries.

### Article 16 (Changes to These Terms)

The Developer may change these Terms without notice to the User when the Developer considers it necessary. The changed Terms take effect when they are posted on the website operated by the Developer (https://haji.men).

### Article 17 (Governing Law)

These Terms are governed by and construed in accordance with the laws of Japan.

---

Established on October 30, 2026

Revised on November 16, 2026
