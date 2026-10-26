#![forbid(unsafe_code)]

//! エンジンの返事が間に合わなかったキーを，送った順に反映するための並べ方

/// 返事を調べた結果
pub enum Poll<T> {
    /// 届いた
    Ready(T),
    /// もう届かない(エンジンとの接続が切れた)
    Gone,
    /// まだ届いていない
    Waiting,
}

/// queue を送った順に調べ，届いた返事を順に返す．まだ届いていないものがあれば，それとそのあとのものは残す
/// (あとのキーの返事を先に反映すると，確定した文が組み立て中に戻るなど，表示の順が入れ替わる)
pub fn drain_in_order<P, T>(
    queue: Vec<P>,
    mut poll: impl FnMut(&P) -> Poll<T>,
) -> (Vec<T>, Vec<P>) {
    let mut ready = Vec::new();
    let mut remaining = queue.into_iter();
    while let Some(pending) = remaining.next() {
        match poll(&pending) {
            Poll::Ready(value) => ready.push(value),
            Poll::Gone => {}
            Poll::Waiting => {
                let mut waiting = vec![pending];
                waiting.extend(remaining);
                return (ready, waiting);
            }
        }
    }
    (ready, Vec::new())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 届いた返事を送った順に返す() {
        let (ready, waiting) = drain_in_order(vec![1, 2, 3], |n| Poll::Ready(*n * 10));
        assert_eq!(ready, vec![10, 20, 30]);
        assert!(waiting.is_empty());
    }

    #[test]
    fn 先の返事が届いていなければあとの返事も反映しない() {
        // 2 番目がまだ．3 番目は届いていても先に反映しない
        let (ready, waiting) = drain_in_order(vec![1, 2, 3], |n| {
            if *n == 2 {
                Poll::Waiting
            } else {
                Poll::Ready(*n)
            }
        });
        assert_eq!(ready, vec![1]);
        assert_eq!(waiting, vec![2, 3]);
    }

    #[test]
    fn 接続が切れた返事は捨てて続ける() {
        let (ready, waiting) = drain_in_order(vec![1, 2, 3], |n| {
            if *n == 1 {
                Poll::Gone
            } else {
                Poll::Ready(*n)
            }
        });
        assert_eq!(ready, vec![2, 3]);
        assert!(waiting.is_empty());
    }
}
