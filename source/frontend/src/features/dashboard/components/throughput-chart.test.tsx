import type { ReactNode } from "react";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { ThroughputChart } from "./throughput-chart";

const { chartSpy, cursorSpy } = vi.hoisted(() => ({ chartSpy: vi.fn(), cursorSpy: vi.fn() }));
vi.mock("recharts", () => ({
  ResponsiveContainer: ({ children }: { children: ReactNode }) => <>{children}</>,
  LineChart: ({ data, children }: { data: unknown; children: ReactNode }) => {
    chartSpy(data);
    return <div>{children}</div>;
  },
  Line: () => null,
  CartesianGrid: () => null,
  XAxis: () => null,
  YAxis: () => null,
  Tooltip: ({ cursor }: { cursor: unknown }) => {
    cursorSpy(cursor);
    return null;
  },
}));

describe("ThroughputChart", () => {
  it("plots account-type lines over time, leaves gaps and switches the model/reasoning selection", async () => {
    const user = userEvent.setup();
    const buckets = ["2026-10-06T10:00:00Z", "2026-10-06T11:00:00Z", "2026-10-06T12:00:00Z"];
    render(<ThroughputChart buckets={buckets} data={[
      { bucketStart: buckets[0], model: "gpt-6.1-sol", reasoningEffort: "medium", planType: "pro", averageTokensPerSecond: 70, sampleCount: 1 },
      { bucketStart: buckets[2], model: "gpt-6.1-sol", reasoningEffort: "medium", planType: "pro", averageTokensPerSecond: 80, sampleCount: 2 },
      { bucketStart: buckets[2], model: "gpt-6.1-sol", reasoningEffort: "medium", planType: "prolite", averageTokensPerSecond: 90, sampleCount: 1 },
      { bucketStart: buckets[1], model: "gpt-6.1-sol", reasoningEffort: "ultra", planType: "pro", averageTokensPerSecond: 100, sampleCount: 1 },
    ]} />);
    expect(screen.getByRole("region", { name: "Average generated tokens per second" })).toBeInTheDocument();
    expect(screen.getByText("Pro 200")).toBeInTheDocument();
    expect(screen.getByText("Business Premium")).toBeInTheDocument();
    expect(chartSpy).toHaveBeenLastCalledWith([
      { timestamp: Date.parse(buckets[0]), plan0: 70, plan0Samples: 1, plan1: null },
      { timestamp: Date.parse(buckets[1]), plan0: null, plan1: null },
      { timestamp: Date.parse(buckets[2]), plan0: 80, plan0Samples: 2, plan1: 90, plan1Samples: 1 },
    ]);
    expect(cursorSpy).toHaveBeenLastCalledWith({ stroke: "var(--muted-foreground)", strokeWidth: 1, strokeOpacity: 0.6 });
    await user.click(screen.getByRole("combobox", { name: "Throughput model and reasoning" }));
    await user.click(screen.getByRole("option", { name: "gpt-6.1-sol (ultra)" }));
    expect(chartSpy).toHaveBeenLastCalledWith([
      { timestamp: Date.parse(buckets[0]), plan0: null },
      { timestamp: Date.parse(buckets[1]), plan0: 100, plan0Samples: 1 },
      { timestamp: Date.parse(buckets[2]), plan0: null },
    ]);
    await user.click(screen.getByRole("button", { name: "Reset selection" }));
    expect(screen.getByRole("combobox", { name: "Throughput model and reasoning" })).toHaveTextContent("medium");
  });

  it("shows an empty state when completed requests have no usable timing", () => {
    render(<ThroughputChart data={[]} buckets={[]} />);
    expect(screen.getByText("No throughput samples yet")).toBeInTheDocument();
  });
});
