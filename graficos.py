from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

results = Path("results")
models = ["eav", "jsonb_gin", "jsonb_btree", "udt"]
write_order = [10, 30, 50, 70, 90]

df = pd.read_csv(
    results / "benchmark_resultados.csv",
    dtype={"modelo": str, "ratio": str},
)
df["writes_pct"] = df["ratio"].str.split("/").str[1].astype(int)

# Gráfico 1: TPS promedio por mezcla; barras de error = desviación estándar
summary = (
    df.groupby(["writes_pct", "modelo"])["tps"]
    .agg(["mean", "std"])
    .reset_index()
)

fig, ax = plt.subplots(figsize=(8, 5))
for model in models:
    series = (
        summary[summary["modelo"] == model]
        .set_index("writes_pct")
        .reindex(write_order)
    )
    ax.errorbar(
        write_order,
        series["mean"],
        yerr=series["std"],
        marker="o",
        capsize=3,
        label=model,
    )

ax.set(
    title="TPS según porcentaje de escrituras",
    xlabel="% de escrituras",
    ylabel="Transacciones por segundo (TPS)",
    xticks=write_order,
)
ax.legend(title="Modelo")
ax.grid(axis="y", alpha=0.3)
fig.tight_layout()
fig.savefig(results / "grafico1_tps.png", dpi=180)
plt.close(fig)

# Gráfico 2: tamaño total por modelo; EAV suma sus dos tablas
size_parts = []
for model in models:
    part = pd.read_csv(results / f"sizes_{model}.csv")
    part["modelo"] = model
    size_parts.append(part[["modelo", "bytes_total"]])

sizes = pd.concat(size_parts, ignore_index=True)
size_gib = (
    sizes.groupby("modelo")["bytes_total"].sum()
    .reindex(models)
    / (1024 ** 3)
)

fig, ax = plt.subplots(figsize=(7, 5))
size_gib.plot(kind="bar", ax=ax, color="steelblue")
ax.set(
    title="Tamaño total en disco por modelo",
    xlabel="Modelo",
    ylabel="GiB",
)
ax.tick_params(axis="x", rotation=0)
fig.tight_layout()
fig.savefig(results / "grafico2_tamanos.png", dpi=180)
plt.close(fig)

# Gráfico 3: WAL promedio por modelo y ratio, en MiB
wal = (
    df.groupby(["writes_pct", "modelo"])["wal_bytes"]
    .mean()
    .unstack()
    .reindex(index=write_order, columns=models)
    / (1024 ** 2)
)

fig, ax = plt.subplots(figsize=(9, 5))
wal.plot(kind="bar", ax=ax)
ax.set(
    title="WAL promedio por corrida y mezcla",
    xlabel="% de escrituras",
    ylabel="WAL generado (MiB)",
)
ax.tick_params(axis="x", rotation=0)
ax.legend(title="Modelo")
fig.tight_layout()
fig.savefig(results / "grafico3_wal.png", dpi=180)
plt.close(fig)