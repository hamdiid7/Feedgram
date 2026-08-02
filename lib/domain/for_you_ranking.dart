/// Tunables for the For You ranking.
class ForYouWeights {
  const ForYouWeights({
    this.windowDays = 0,
    this.priorViews = 500,
    this.minViews = 0,
    this.maxPerPage = 3,
    this.recencyBoost = 0.25,
    this.recencyHalfLifeDays = 3,
  });

  /// Rolling window in days, or **0 for no limit**.
  ///
  /// Unlimited by default: the feed should rank everything it holds rather than
  /// running out. [recencyBoost] is what keeps recent posts ahead, instead of a
  /// hard cutoff that made the feed simply end.
  final int windowDays;

  /// `k` — the Bayesian prior's weight, expressed in views.
  ///
  /// Read it as "every post starts out having been seen [priorViews] times with
  /// average engagement". A post needs roughly this much real volume before its
  /// own ratio outweighs the prior.
  final int priorViews;

  /// Minimum views to rank, or 0 for none.
  ///
  /// Zero by default because the smoothing already handles thin evidence: a
  /// 2-view, 1-like post scores almost exactly the pool mean rather than 0.5, so
  /// it lands mid-pack instead of winning. The floor is kept as a dial for when
  /// that is not enough.
  final int minViews;

  /// Most posts one channel may contribute to a single page.
  final int maxPerPage;

  /// How much fresher posts are favoured, as a fraction of their score.
  ///
  /// Deliberately mild — 0.25 means a brand-new post is worth at most 25% more
  /// than the same post a long time later. Engagement stays the primary signal;
  /// this only breaks near-ties toward what is current.
  final double recencyBoost;

  /// Age at which the recency bonus is half spent.
  final int recencyHalfLifeDays;

  bool get hasWindow => windowDays > 0;
  int get windowSeconds => windowDays * 86400;
}

/// The ranking expression, as SQL.
///
/// ```
/// engagement = (likes + k·m) / (views + k)
/// score      = engagement × (1 + boost / (1 + ageDays / halfLife))
/// ```
///
/// **Why smoothing is not optional.** A raw ratio lets a post with 2 views and 1
/// like score 0.5 and beat everything real. Fresh posts are the worst case, since
/// reactions land before views accumulate — precisely the posts a "what's good
/// right now" feed reaches for. Pulling low-volume posts toward the mean means an
/// extreme score has to be *earned with volume*.
///
/// **Posts with no reactions at all are ranked by views instead.** A channel with
/// reactions switched off produces no likes however popular it is, so likes÷views
/// says nothing about it. Such posts are scored at the pool mean — the honest "no
/// evidence either way" position — and ordered among themselves by view count,
/// since views are then the only signal that more people saw it.
///
/// The decay uses `1 / (1 + age/halfLife)` rather than a true exponential because
/// SQLite's `exp()` is only present when compiled with
/// `SQLITE_ENABLE_MATH_FUNCTIONS`, which is not guaranteed here.
String forYouScoreSql({
  required String likes,
  required String views,
  required String date,
  required String nowParam,
  required double meanRatio,
  required ForYouWeights weights,
}) {
  final k = weights.priorViews;
  const day = 86400.0;

  // No reactions is not the same as unpopular: treat it as exactly average and
  // let views do the sorting.
  final engagement = 'CASE WHEN $likes = 0 THEN $meanRatio '
      'ELSE (($likes + $k * $meanRatio) / ($views + $k.0)) END';

  final freshness = '(1.0 / (1.0 + '
      '((($nowParam - $date) / $day) / ${weights.recencyHalfLifeDays}.0)))';

  return '(($engagement) * (1.0 + ${weights.recencyBoost} * $freshness))';
}

/// Pooled mean, i.e. `SUM(likes) / SUM(views)` — not the average of per-post
/// ratios.
///
/// The average of ratios would let a hundred tiny posts drag the prior wherever
/// they liked; weighting by volume is what makes it represent "typical
/// engagement".
double pooledMeanRatio({required int totalLikes, required int totalViews}) {
  if (totalViews <= 0) return 0;
  return totalLikes / totalViews;
}
