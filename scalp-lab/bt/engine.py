import numpy as np
from collections import Counter

from bt.stats import metrics


def position_returns(df, pos, fee, slip):
    ret = df["close"].pct_change().fillna(0.0)
    p = pos.shift(1).fillna(0.0)
    gross = p * ret
    d = p.diff().fillna(0.0)
    costs = d.abs() * (fee + slip)
    net = gross - costs
    n_trades = int((d.abs() > 1e-12).sum())
    return net, n_trades


def walk_forward(df, sigs, train_bars, test_bars, fee, slip, tf_min,
                 fee2=None, slip2=None):
    bars_per_year = 365.0 * 24 * 60 / tf_min
    keys = list(sigs.keys())
    if not keys:
        return {"error": "no valid params"}
    oos_parts = []
    oos2_parts = []
    chosen = []
    is_sharpes = []
    total_trades = 0
    t0 = train_bars
    while t0 + test_bars <= len(df):
        best_key, best_is = None, -1e9
        for k in keys:
            a, b = t0 - train_bars, t0
            net, _ = position_returns(df.iloc[a:b], sigs[k].iloc[a:b], fee, slip)
            m = metrics(net.values, bars_per_year)
            if m["sharpe"] > best_is:
                best_is, best_key = m["sharpe"], k
        a, b = t0, t0 + test_bars
        net, trades = position_returns(df.iloc[a:b], sigs[best_key].iloc[a:b], fee, slip)
        oos_parts.append(net.values)
        if fee2 is not None:
            net2, _ = position_returns(df.iloc[a:b], sigs[best_key].iloc[a:b], fee2, slip2)
            oos2_parts.append(net2.values)
        chosen.append(best_key)
        is_sharpes.append(best_is)
        total_trades += trades
        t0 += test_bars
    if not oos_parts:
        return {"error": "not enough bars"}
    oos_ret = np.concatenate(oos_parts)
    mo = metrics(oos_ret, bars_per_year)
    top = Counter(chosen).most_common(1)[0]
    res = {
        "oos": mo,
        "trades": int(total_trades),
        "is_sharpe_avg": float(np.mean(is_sharpes)),
        "folds": int(len(chosen)),
        "param_stability": float(top[1] / len(chosen)),
        "top_param": top[0],
    }
    if oos2_parts:
        mo2 = metrics(np.concatenate(oos2_parts), bars_per_year)
        res["oos_maker"] = mo2
    return res
