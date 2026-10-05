import { useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { Gauge } from "lucide-react";
import { CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";

import { EmptyState } from "@/components/empty-state";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { formatChartDateTime, formatModelLabel, formatPlanType } from "@/utils/formatters";
import { DASHBOARD_CHART_COLORS as colors } from "@/utils/constants";
import type { DashboardThroughput } from "@/features/dashboard/schemas";

type Props = { data: DashboardThroughput[]; buckets: string[] };
type PlotRow = { timestamp: number } & Record<string, number | null>;

export function ThroughputChart({ data, buckets }: Props) {
  const { t } = useTranslation();
  const [selectedKey, setSelectedKey] = useState<string | null>(null);
  const groups = useMemo(() => {
    const grouped = new Map<string, {
      key: string; model: string; reasoningEffort: string | null; label: string; latest: number; samples: number;
    }>();
    for (const item of data) {
      const key = JSON.stringify([item.model, item.reasoningEffort]);
      const group = grouped.get(key) ?? {
        key, model: item.model, reasoningEffort: item.reasoningEffort,
        label: formatModelLabel(item.model, item.reasoningEffort ?? t("dashboard.throughput.unknownReasoning")),
        latest: 0, samples: 0,
      };
      group.latest = Math.max(group.latest, Date.parse(item.bucketStart));
      group.samples += item.sampleCount;
      grouped.set(key, group);
    }
    return [...grouped.values()].sort((a, b) => b.latest - a.latest || b.samples - a.samples || a.label.localeCompare(b.label));
  }, [data, t]);
  const selected = groups.find((group) => group.key === selectedKey) ?? groups[0];
  const { series, chartData } = useMemo(() => {
    const filtered = data.filter((item) => item.model === selected?.model && item.reasoningEffort === selected?.reasoningEffort);
    const allPlans = [...new Set(data.map((item) => item.planType))].sort();
    const plans = [...new Set(filtered.map((item) => item.planType))].sort();
    const series = plans.map((planType, index) => ({
      key: `plan${index}`,
      label: planType === "unknown" ? t("dashboard.throughput.unknownPlan") : formatPlanType(planType),
      planType,
      color: colors[allPlans.indexOf(planType) % colors.length],
    }));
    const timestamps = [...new Set([...buckets.map(Date.parse), ...filtered.map((item) => Date.parse(item.bucketStart))])].sort((a, b) => a - b);
    const rows = new Map<number, PlotRow>();
    for (const timestamp of timestamps) {
      const row: PlotRow = { timestamp };
      for (const entry of series) row[entry.key] = null;
      rows.set(timestamp, row);
    }
    for (const item of filtered) {
      const row = rows.get(Date.parse(item.bucketStart))!;
      const key = series.find((entry) => entry.planType === item.planType)!.key;
      row[key] = item.averageTokensPerSecond;
      row[`${key}Samples`] = item.sampleCount;
    }
    return { series, chartData: [...rows.values()] };
  }, [buckets, data, selected, t]);
  const formatTimestamp = (timestamp: number) => formatChartDateTime(new Date(timestamp).toISOString());

  return (
    <section className="min-w-0 rounded-xl border bg-card p-5" aria-label={t("dashboard.throughput.title")}>
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0">
          <h2 className="text-base font-semibold">{t("dashboard.throughput.title")}</h2>
          <p className="mt-1 text-xs text-muted-foreground">{t("dashboard.throughput.description")}</p>
        </div>
        {selected && (
          <div className="ml-auto flex max-w-full flex-wrap items-center gap-2">
            <Button variant="ghost" size="sm" onClick={() => setSelectedKey(null)}>{t("dashboard.throughput.resetSelection")}</Button>
            <Select value={selected.key} onValueChange={setSelectedKey}>
              <SelectTrigger size="sm" className="w-64 max-w-full" aria-label={t("dashboard.throughput.modelSelection")}>
                <SelectValue />
              </SelectTrigger>
              <SelectContent align="end">
                {groups.map((group) => <SelectItem key={group.key} value={group.key}>{group.label}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
        )}
      </div>
      {data.length === 0 ? (
        <div className="mt-4">
          <EmptyState icon={Gauge} title={t("dashboard.throughput.emptyTitle")} description={t("dashboard.throughput.emptyDescription")} />
        </div>
      ) : (
        <>
          <div className="mt-4 h-72 rounded-lg border border-border/60 bg-background/20 p-2">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={chartData} margin={{ top: 16, right: 20, left: 12, bottom: 12 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" vertical={false} opacity={0.5} />
                <XAxis dataKey="timestamp" type="number" domain={["dataMin", "dataMax"]} ticks={chartData.filter((_, index) => index % Math.max(1, Math.ceil(chartData.length / 6)) === 0 || index === chartData.length - 1).map((row) => row.timestamp)} minTickGap={50} tickFormatter={formatTimestamp} tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} axisLine={false} tickLine={false} />
                <YAxis domain={[0, "auto"]} width={58} label={{ value: "tok/s", angle: -90, position: "insideLeft", fill: "var(--muted-foreground)", fontSize: 12 }} tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} axisLine={false} tickLine={false} tickFormatter={(value: number) => value.toFixed(0)} />
                <Tooltip cursor={{ stroke: "var(--muted-foreground)", strokeWidth: 1, strokeOpacity: 0.6 }} content={(props) => (
                  props.active && props.payload?.length ? (
                    <div className="rounded-lg border bg-popover p-3 text-xs shadow-md">
                      <div className="mb-2 font-medium">{formatTimestamp(Number(props.label))}</div>
                      {props.payload.map((entry) => (
                        <div key={String(entry.dataKey)} className="flex items-center gap-3 py-1">
                          <span className="h-4 w-1 rounded-full" style={{ backgroundColor: entry.color }} />
                          <span>{entry.name}</span>
                          <span className="ml-auto tabular-nums">{Number(entry.value).toFixed(1)} tok/s</span>
                          <span className="text-muted-foreground">{t("dashboard.throughput.samples", { count: Number(entry.payload[`${String(entry.dataKey)}Samples`]) })}</span>
                        </div>
                      ))}
                    </div>
                  ) : null
                )} />
                {series.map((entry) => (
                  <Line key={entry.key} dataKey={entry.key} name={entry.label} stroke={entry.color} strokeWidth={2} type="monotone" dot={chartData.filter((row) => row[entry.key] !== null).length === 1 ? { r: 3 } : false} activeDot={{ r: 4, strokeWidth: 1.5, fill: "var(--popover)" }} connectNulls={false} isAnimationActive={false} />
                ))}
              </LineChart>
            </ResponsiveContainer>
          </div>
          <div className="mt-3 flex flex-wrap gap-x-5 gap-y-2 text-xs">
            {series.map((entry) => (
              <span key={entry.key} className="inline-flex items-center gap-2">
                <span className="h-1 w-5 rounded-full" style={{ backgroundColor: entry.color }} />{entry.label}
              </span>
            ))}
          </div>
        </>
      )}
    </section>
  );
}
