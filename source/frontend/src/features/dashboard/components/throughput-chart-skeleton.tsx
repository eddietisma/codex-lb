import { useTranslation } from "react-i18next";

import { Skeleton } from "@/components/ui/skeleton";

export function ThroughputChartSkeleton() {
  const { t } = useTranslation();
  return (
    <div className="min-w-0 rounded-xl border bg-card p-5" role="status" aria-label={t("common.loading")}>
      <div aria-hidden="true">
        <Skeleton className="h-5 w-64 max-w-full" />
        <Skeleton className="mt-1 h-4 w-full max-w-lg" />
        <div className="mt-4 h-72 rounded-lg border border-border/60 p-6">
          <Skeleton className="h-full w-full" />
        </div>
        <div className="mt-3 flex gap-5">
          <Skeleton className="h-4 w-20" />
          <Skeleton className="h-4 w-20" />
        </div>
      </div>
    </div>
  );
}
