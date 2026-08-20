import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

/**
 * 统一页头 —— 简洁留白风的核心元素之一。
 * 所有页面共用：左侧（可选小图标 + 标题 + 副标题），右侧操作区。
 * 不负责水平留白：水平 padding 由页面容器统一处理（px-8），
 * 保证每个页面的页头与内容区完全对齐。
 */
export function PageHeader({
  icon,
  title,
  subtitle,
  actions,
  className,
}: {
  icon?: ReactNode;
  title: ReactNode;
  subtitle?: ReactNode;
  actions?: ReactNode;
  className?: string;
}) {
  return (
    <header
      className={cn(
        "flex flex-wrap items-center justify-between gap-x-6 gap-y-3 pt-8 pb-6",
        className,
      )}
    >
      <div className="min-w-0">
        {icon && (
          <div className="mb-1.5 flex items-center gap-1.5 text-sm text-muted-foreground">
            {icon}
          </div>
        )}
        <h1 className="text-2xl font-semibold tracking-tight text-foreground">
          {title}
        </h1>
        {subtitle && (
          <p className="mt-1 text-sm text-muted-foreground">{subtitle}</p>
        )}
      </div>
      {actions && (
        <div className="flex shrink-0 flex-wrap items-center gap-3">{actions}</div>
      )}
    </header>
  );
}
