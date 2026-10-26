use crate::handwriting::ink::{merge_segments, Point};
use std::sync::mpsc::{self, Receiver, Sender};
use windows::Foundation::Point as InkPoint;
use windows::Win32::System::Com::{CoInitializeEx, COINIT_MULTITHREADED};
use windows::UI::Input::Inking::{InkManager, InkRecognitionTarget, InkStrokeBuilder};
use windows_collections::IIterable;
use windows_core::Result;

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
}

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
            .name("s90-handwriting-recognizer".into())
            .spawn(move || run(&receiver, &done))?;
        Ok(Self { jobs })
    }

    pub fn recognize(&self, generation: u64, strokes: Vec<Vec<Point>>) {
        let _ = self.jobs.send(Job {
            generation,
            strokes,
        });
    }
}

fn run(jobs: &Receiver<Job>, done: &dyn Fn(u64, Outcome)) {
    // SAFETY: このスレッドで一度だけ呼ぶ．WinRT の部品をこのスレッドの中だけで作って使うための初期化
    let _ = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
    while let Ok(mut job) = jobs.recv() {
        // 書き足しのあいだにたまった頼みは，いちばん新しいものだけを読む
        while let Ok(newer) = jobs.try_recv() {
            job = newer;
        }
        let outcome = match recognize(&job.strokes) {
            Ok(Some(candidates)) => Outcome::Candidates(candidates),
            Ok(None) => Outcome::Unavailable,
            Err(_) => Outcome::Candidates(Vec::new()),
        };
        done(job.generation, outcome);
    }
}

/// 日本語の認識器が無ければ None
fn recognize(strokes: &[Vec<Point>]) -> Result<Option<Vec<String>>> {
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
    let results = manager.RecognizeAsync(InkRecognitionTarget::All)?.join()?;
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
