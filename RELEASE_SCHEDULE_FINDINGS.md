# Economic Indicators Release Schedule

Based on the analysis of the workspace configuration and typical release calendars, here is the estimated release schedule for the requested indicators.

## Brazil Indicators

| Series | Source | Typical Release | Approx Lag Days | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Industrial Production (PIM-PF)**<br>*(General & Components)* | IBGE | **~35-40 days after month end**<br>(e.g., early Nov for Sept) | **35-40** | Components (Intermediate, Semidurable, etc.) are released simultaneously with the General Index. |
| **Real Average Earnings**<br>*(Manufacturing)* | CNI | **~25-35 days after month end**<br>(Mid-to-late next month) | **25-35** | Part of "Indicadores Industriais". Usually released mid-month. Workspace config suggests ~25 days. |
| **Energy Consumption**<br>*(Comm, Res, Ind)* | EPE / Eletrobras | **~30-45 days after month end**<br>(End of next month in "Resenha Mensal") | **30-45** | "Resenha Mensal do Mercado de Energia Elétrica" is typically published at the end of the following month. |
| **Consumer Confidence (ICC)** | Fecomercio | **~0-5 days after month end**<br>(Late ref month or very early next) | **0-5** | Confidence surveys are often released near the end of the reference month. |
| **Confidence Indexes (ICS, ISA, IE)** | FGV | **~0 days (Ref Month)**<br>(Previews mid-month, Final end-month) | **0** | FGV releases Previews around the 15th-20th and Final results at the end of the reference month or 1st day of next. |
| **Credit Statistics**<br>*(Total Credit, M1, Savings)* | BCB | **~26-30 days after month end**<br>(Last week of next month) | **26-30** | "Estatísticas Monetárias e de Crédito" are typically released between the 26th and 29th of the following month. |

## US Indicators (FRED)

| Series | Source | Typical Release | Approx Lag Days | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **UMCSENT**<br>*(Consumer Sentiment)* | U. of Michigan | **Ref Month**<br>(Prelim ~15th, Final ~End of month) | **0** | Preliminary data is available mid-month; Final is available at month end. |
| **HOUST**<br>*(Housing Starts)* | Census / HUD | **~17-19 days after month end**<br>(~12th business day) | **17-19** | "New Residential Construction" report. |
| **RSAFS**<br>*(Advance Retail Sales)* | Census Bureau | **~15-16 days after month end**<br>(~13th of next month) | **15-16** | "Advance Monthly Sales for Retail and Food Services". |
| **TCU**<br>*(Capacity Utilization)* | Federal Reserve | **~15-17 days after month end**<br>(Mid-month) | **15-17** | Released with Industrial Production (G.17) around the 15th-17th. |

## Summary of Findings

1.  **IBGE PIM-PF**: The components (Intermediate, Semidurable, etc.) follow the same schedule as the General Industry Index. The lag is typically around **35-40 days** (e.g., September data released in early November).
2.  **CNI**: The "Indicadores Industriais" (including earnings) are typically released in the middle of the following month. Workspace configuration suggests a **25-day** lag, which aligns with a mid-to-late month release.
3.  **Confidence Indexes (FGV/Fecomercio)**: These are "soft" data and are released much faster, often within the reference month (0 lag) or very shortly after.
4.  **BCB Credit**: These are "hard" financial data, released with a consistent lag of about **4 weeks** (late next month).
5.  **US Data**: Generally released faster than Brazilian "hard" data, with lags of **15-20 days** for production/sales and **0 days** for sentiment.
