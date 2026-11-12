use crate::handwriting::ink::{merge_segments, Point};
use std::sync::mpsc::{self, Receiver, Sender};
use std::time::{Duration, Instant};
use windows::Foundation::Point as InkPoint;
use windows::Win32::System::Com::{CoInitializeEx, COINIT_MULTITHREADED};
use windows::UI::Input::Inking::{InkManager, InkRecognitionTarget, InkStrokeBuilder};
use windows_collections::IIterable;
use windows_core::Result;
use windows_future::AsyncStatus;

/// 認識の結果
pub enum Outcome {
    /// よさそうな順の文字列
    Candidates(Vec<String>),
    /// 日本語の手書き認識が入っていない
    Unavailable,
}

struct Job {
    generation: u64,
    strokes: Vec<Vec<Point>>,
    timeout: Duration,
}

/// 認識の終わりを確かめる間隔
const POLL_INTERVAL: Duration = Duration::from_millis(10);

/// 書いた線を Windows の手書き認識(Windows.UI.Input.Inking)で読む．端末の中だけで読み，通信しない．
/// 認識は待つことがあるので，窓のスレッドを止めないよう別のスレッドで行う
pub struct Recognizer {
    jobs: Sender<Job>,
}

impl Recognizer {
    /// done は認識を終えるたびに認識のスレッドから呼ばれる
    pub fn start(done: impl Fn(u64, Outcome) + Send + 'static) -> std::io::Result<Self> {
        let (jobs, receiver) = mpsc::channel();
        std::thread::Builder::new()
            .name("hajime-handwriting-recognizer".into())
            .spawn(move || run(&receiver, &done))?;
        Ok(Self { jobs })
    }

    /// timeout を過ぎても読み終わらなければ，読むのをやめて候補を空にする
    pub fn recognize(&self, generation: u64, strokes: Vec<Vec<Point>>, timeout: Duration) {
        let _ = self.jobs.send(Job {
            generation,
            strokes,
            timeout,
        });
    }
}

fn run(jobs: &Receiver<Job>, done: &dyn Fn(u64, Outcome)) {
    // SAFETY: このスレッドで一度だけ呼ぶ．WinRT の部品をこのスレッドの中だけで作って使うための初期化
    let _ = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
    // 日本語の認識器を選んだ InkManager．作って認識器を選ぶのに 0.1 秒ほどかかるので，このスレッドで使い回す
    let mut ink = None;
    while let Ok(mut job) = jobs.recv() {
        // 書き足しのあいだにたまった頼みは，いちばん新しいものだけを読む
        while let Ok(newer) = jobs.try_recv() {
            job = newer;
        }
        let outcome = match recognize(&mut ink, &job.strokes, job.timeout) {
            Ok(Some(candidates)) => Outcome::Candidates(candidates),
            Ok(None) => Outcome::Unavailable,
            Err(_) => Outcome::Candidates(Vec::new()),
        };
        done(job.generation, outcome);
    }
}

/// 日本語の認識器が無ければ None．ink は前に使った InkManager(無ければ作る)．読み終えて線を消せたら，次のために ink に戻す
fn recognize(
    ink: &mut Option<InkManager>,
    strokes: &[Vec<Point>],
    timeout: Duration,
) -> Result<Option<Vec<String>>> {
    let manager = match ink.take() {
        Some(manager) => manager,
        None => match japanese_manager()? {
            Some(manager) => manager,
            None => return Ok(None),
        },
    };
    let read = read(&manager, strokes, timeout)?;
    // 読み終えなかった(やめた)ときは使い回さず，次は作り直す
    if read.is_some() && clear(&manager).unwrap_or(false) {
        *ink = Some(manager);
    }
    Ok(Some(read.unwrap_or_default()))
}

/// 線をすべて消す．消し切れたら true
fn clear(manager: &InkManager) -> Result<bool> {
    let strokes = manager.GetStrokes()?;
    for index in 0..strokes.Size()? {
        strokes.GetAt(index)?.SetSelected(true)?;
    }
    manager.DeleteSelected()?;
    Ok(manager.GetStrokes()?.Size()? == 0)
}

/// 日本語の認識器を選んだ InkManager．日本語の認識器が無ければ None
fn japanese_manager() -> Result<Option<InkManager>> {
    let manager = InkManager::new()?;
    let recognizers = manager.GetRecognizers()?;
    let mut japanese = None;
    for index in 0..recognizers.Size()? {
        let recognizer = recognizers.GetAt(index)?;
        let name = recognizer.Name()?.to_string_lossy();
        if name.contains("日本語") || name.contains("Japanese") {
            japanese = Some(recognizer);
            break;
        }
    }
    let Some(japanese) = japanese else {
        return Ok(None);
    };
    manager.SetDefaultRecognizer(&japanese)?;
    Ok(Some(manager))
}

/// 線を読んだ候補．timeout までに読み終わらなければ，読むのをやめて None
fn read(
    manager: &InkManager,
    strokes: &[Vec<Point>],
    timeout: Duration,
) -> Result<Option<Vec<String>>> {
    let builder = InkStrokeBuilder::new()?;
    for stroke in strokes {
        let mut points: Vec<InkPoint> = stroke
            .iter()
            .map(|point| InkPoint {
                X: point.x,
                Y: point.y,
            })
            .collect();
        // 点を 1 つだけ打った線(点画)も線として読めるよう，同じ点を 2 つにする
        if let [only] = points.as_slice() {
            points.push(*only);
        }
        if points.is_empty() {
            continue;
        }
        let stroke = builder.CreateStroke(&IIterable::<InkPoint>::from(points))?;
        manager.AddStroke(&stroke)?;
    }
    let operation = manager.RecognizeAsync(InkRecognitionTarget::All)?;
    let deadline = Instant::now() + timeout;
    while operation.Status()? == AsyncStatus::Started {
        if Instant::now() >= deadline {
            let _ = operation.Cancel();
            return Ok(None);
        }
        std::thread::sleep(POLL_INTERVAL);
    }
    let results = operation.GetResults()?;
    let mut segments = Vec::new();
    for index in 0..results.Size()? {
        let texts = results.GetAt(index)?.GetTextCandidates()?;
        let mut candidates = Vec::new();
        for position in 0..texts.Size()? {
            candidates.push(texts.GetAt(position)?.to_string_lossy());
        }
        segments.push(candidates);
    }
    Ok(Some(merge_segments(segments)))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 線分を 20 に分けた点の列．jitter で点を少しずらす(同じ字の書き方を変える)
    fn line(from: (f32, f32), to: (f32, f32), jitter: f32) -> Vec<Point> {
        (0..=20)
            .map(|step| {
                let t = step as f32 / 20.0;
                let wobble = jitter * ((step as f32 * 1.7).sin());
                Point {
                    x: from.0 + (to.0 - from.0) * t + wobble,
                    y: from.1 + (to.1 - from.1) * t - wobble,
                }
            })
            .collect()
    }

    /// いくつかの字(一・二・三・十・土・口・人・大・川・小・工・上)を書き方を変えて書いた線
    fn samples() -> Vec<Vec<Vec<Point>>> {
        type Segment = ((f32, f32), (f32, f32));
        let shapes: Vec<Vec<Segment>> = vec![
            vec![((10.0, 50.0), (90.0, 50.0))],
            vec![((20.0, 35.0), (80.0, 35.0)), ((10.0, 70.0), (90.0, 70.0))],
            vec![
                ((20.0, 20.0), (80.0, 20.0)),
                ((25.0, 50.0), (75.0, 50.0)),
                ((10.0, 85.0), (90.0, 85.0)),
            ],
            vec![((10.0, 50.0), (90.0, 50.0)), ((50.0, 10.0), (50.0, 90.0))],
            vec![
                ((20.0, 45.0), (80.0, 45.0)),
                ((50.0, 15.0), (50.0, 85.0)),
                ((10.0, 85.0), (90.0, 85.0)),
            ],
            vec![
                ((20.0, 20.0), (20.0, 80.0)),
                ((20.0, 20.0), (80.0, 20.0)),
                ((80.0, 20.0), (80.0, 80.0)),
                ((20.0, 80.0), (80.0, 80.0)),
            ],
            vec![((50.0, 10.0), (15.0, 90.0)), ((45.0, 35.0), (90.0, 90.0))],
            vec![
                ((10.0, 40.0), (90.0, 40.0)),
                ((50.0, 10.0), (15.0, 90.0)),
                ((50.0, 40.0), (90.0, 90.0)),
            ],
            vec![
                ((25.0, 15.0), (20.0, 85.0)),
                ((50.0, 20.0), (50.0, 75.0)),
                ((78.0, 10.0), (80.0, 90.0)),
            ],
            vec![
                ((50.0, 10.0), (50.0, 90.0)),
                ((30.0, 40.0), (15.0, 70.0)),
                ((70.0, 40.0), (85.0, 70.0)),
            ],
            vec![
                ((20.0, 20.0), (80.0, 20.0)),
                ((50.0, 20.0), (50.0, 80.0)),
                ((10.0, 80.0), (90.0, 80.0)),
            ],
            vec![
                ((50.0, 10.0), (50.0, 85.0)),
                ((50.0, 45.0), (80.0, 45.0)),
                ((10.0, 85.0), (90.0, 85.0)),
            ],
        ];
        let mut samples = Vec::new();
        for jitter in [0.0, 1.5, 3.0] {
            for shape in &shapes {
                samples.push(
                    shape
                        .iter()
                        .map(|(from, to)| line(*from, *to, jitter))
                        .collect(),
                );
            }
        }
        samples
    }

    /// 使い回した InkManager で読んだ候補が，毎回作り直して読んだ候補(前のやり方)と同じか確かめ，時間を比べる
    /// (Windows の日本語の手書き認識が要るので，ふだんは動かさない)
    #[test]
    #[ignore = "Windows の日本語の手書き認識が要る(--ignored で動かす)"]
    fn reused_manager_reads_the_same() {
        // SAFETY: このスレッドで COM を使う前に呼ぶ
        let _ = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
        let timeout = Duration::from_secs(10);
        let samples = samples();
        let start = Instant::now();
        let fresh: Vec<_> = samples
            .iter()
            .map(|strokes| recognize(&mut None, strokes, timeout).unwrap())
            .collect();
        let fresh_time = start.elapsed();
        let mut ink = None;
        let start = Instant::now();
        let reused: Vec<_> = samples
            .iter()
            .map(|strokes| recognize(&mut ink, strokes, timeout).unwrap())
            .collect();
        let reused_time = start.elapsed();
        assert!(fresh.iter().all(Option::is_some));
        assert_eq!(fresh, reused);
        let per = |time: Duration| time.as_secs_f64() * 1000.0 / samples.len() as f64;
        println!(
            "{} 字: 作り直す {:.1} ms / 使い回す {:.1} ms(1 字あたり)．先頭の候補: {:?}",
            samples.len(),
            per(fresh_time),
            per(reused_time),
            fresh
                .iter()
                .map(|candidates| candidates.as_ref().and_then(|list| list.first().cloned()))
                .collect::<Vec<_>>()
        );
    }
}
