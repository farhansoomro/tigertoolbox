-- Use either the nexus DB or ReadTrace DB
USE sqlnexus
--USE PerfAnalysis
GO

-- Get Top Unique Batches same as in ReadTrace report
-- From here we can get the Query Hash that allows us to search for the denormalized version of the queries in case we want to execute for repro purposes
SELECT ROW_NUMBER() OVER(ORDER BY CPU DESC) AS QueryNumber, HashID, Executes, CPU, Duration, Reads, Writes, Attentions, [NormText]
FROM (SELECT a.HashID,
		SUM(CompletedEvents) AS Executes,
		SUM(TotalCPU) AS CPU,
		SUM(TotalDuration) AS Duration,
		SUM(TotalReads) AS Reads,
		SUM(TotalWrites) AS Writes,
		SUM(AttentionEvents) AS Attentions, 
		--(SELECT TOP 1 StartTime FROM ReadTrace.tblTimeIntervals i ORDER BY StartTime) AS [StartTime],
		--(SELECT TOP 1 EndTime FROM ReadTrace.tblTimeIntervals i ORDER BY EndTime DESC) AS [EndTime],
		(SELECT CAST(NormText AS NVARCHAR(4000)) FROM ReadTrace.tblUniqueBatches b WHERE b.HashID = a.HashID) AS [NormText],
		ROW_NUMBER() OVER(ORDER BY SUM(TotalCPU) desc) AS CPUDesc,
		ROW_NUMBER() OVER(ORDER BY SUM(TotalCPU) asc) AS CPUAsc,
		ROW_NUMBER() OVER(ORDER BY SUM(TotalDuration) desc) AS DurationDesc,
		ROW_NUMBER() OVER(ORDER BY SUM(TotalDuration) asc) AS DurationAsc,
		ROW_NUMBER() OVER(ORDER BY SUM(TotalReads) desc) AS ReadsDesc,
		ROW_NUMBER() OVER(ORDER BY SUM(TotalReads) asc) AS ReadsAsc,
		ROW_NUMBER() OVER(ORDER BY SUM(TotalWrites) desc) AS WritesDesc,
		ROW_NUMBER() OVER(ORDER BY SUM(TotalWrites) asc) AS WritesAsc
	FROM ReadTrace.tblBatchPartialAggs a
	GROUP BY a.HashID
) AS Outcome
WHERE CPUDesc <= 10 OR CPUAsc <= 10 OR DurationDesc <= 10 OR DurationAsc <= 10 
	OR ReadsDesc <= 10 OR ReadsAsc <= 10 OR WritesDesc <= 10 OR WritesAsc <= 10
ORDER BY CPU DESC
OPTION (RECOMPILE)
GO

-- Get all statements for specific Query Hash
-- Replace Query Hash for the one you want to serach for from the previous query
SELECT DISTINCT LTRIM(RTRIM(REPLACE(t2.TextData, CHAR(9), ''))) AS TextData, t2.Reads*8 AS Read_KB, t2.[DBID]
	,t2.Duration/1000 As Duration_ms, t2.CPU, t2.HashID
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [NormalizedTextData]
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblBatches] t2
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t2.HashID = -6584980619987316302 -- Replace Query Hash for the one you want to serach for from the previous query
	AND t2.TextData IS NOT NULL
--ORDER BY Duration DESC
--ORDER BY CPU DESC
ORDER BY Reads*8 DESC
GO

-- Get all statements ordered by...
SELECT DISTINCT LTRIM(RTRIM(REPLACE(t2.TextData, CHAR(9), ''))) AS TextData, t2.Reads*8 AS Read_KB, t2.[DBID]
	,t2.Duration/1000 As Duration_ms, t2.CPU, t2.HashID
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [NormalizedTextData]
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblBatches] t2
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t2.TextData IS NOT NULL
--ORDER BY t2.Duration/1000 DESC
--ORDER BY t2.CPU DESC
ORDER BY t2.Reads*8 DESC
GO

-- Get list of errors
SELECT [DBID],[Error],
	COUNT(*) AS [Nr_Events],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(text,'%.*ls','%'),'%d','%'),'%ls','%'),'%S_MSG','%'),'%S_PGID','%'),'%#016I64x','%'),'%p','%'),'%08x','%'),'%u','%'),'%I64d','%'),'%s','%'),'%ld','%'),'%lx','%'), '%%%', '%') 
		FROM sys.messages WHERE message_id = [Error] AND language_id = 1033) AS [Error_Msg]
FROM [ReadTrace].[tblInterestingEvents]
WHERE [Error] IS NOT NULL AND [DBID] > 4
GROUP BY [Error], [DBID]
ORDER BY [DBID], [Error]
GO

-- Get normalized batches with errors
SELECT DISTINCT t1.[DBID]
	,t1.[TextData] AS [Event]
--	,t1.[ObjectID]
    ,t1.[Error]
--	,t1.[BatchSeq]
	,t2.[HashID]
	,LTRIM(REPLACE(REPLACE(t2.[TextData],CHAR(10),''),CHAR(13),'')) AS [TextData]
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
	,(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(text,'%.*ls','%'),'%d','%'),'%ls','%'),'%S_MSG','%'),'%S_PGID','%'),'%#016I64x','%'),'%p','%'),'%08x','%'),'%u','%'),'%I64d','%'),'%s','%'),'%ld','%'),'%lx','%'), '%%%', '%') 
	FROM sys.messages WHERE message_id = [Error] AND language_id = 1033) AS [Error_Msg]
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblInterestingEvents] t1
INNER JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t1.[DBID] > 2 
	AND t2.TextData IS NOT NULL
	AND t1.TextData LIKE 'Error:%'
ORDER BY [Error], [DBID] 
GO

-- Get summary of batches with errors
SELECT DISTINCT t1.[DBID]
	--,t1.[TextData] AS [Event]
    ,t1.[Error]
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
	,(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(text,'%.*ls','%'),'%d','%'),'%ls','%'),'%S_MSG','%'),'%S_PGID','%'),'%#016I64x','%'),'%p','%'),'%08x','%'),'%u','%'),'%I64d','%'),'%s','%'),'%ld','%'),'%lx','%'), '%%%', '%') 
	FROM sys.messages WHERE message_id = [Error] AND language_id = 1033) AS [Error_Msg]
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblInterestingEvents] t1
INNER JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t1.[DBID] > 2 
	AND t2.TextData IS NOT NULL
	AND t1.TextData LIKE 'Error:%'
ORDER BY [Error], [DBID] 
GO

-- Get list of interesting events
SELECT DISTINCT te.name AS [Event_Name], COUNT(Seq) AS Number_Events, e.trace_event_id
FROM ReadTrace.tblInterestingEvents x
INNER JOIN ReadTrace.trace_events e ON x.EventID = e.trace_event_id
INNER JOIN sys.trace_events te ON e.trace_event_id = te.trace_event_id
GROUP BY te.name, e.trace_event_id
ORDER BY 2 DESC

-- Get normalized batches with Lock escalations
-- https://docs.microsoft.com/sql/relational-databases/event-classes/lock-escalation-event-class
SELECT DISTINCT t1.[DBID]
    ,t1.[EventID]
	,t1.[EventSubclass]
	, CASE WHEN t1.[EventSubclass] = 0 THEN 'LOCK_THRESHOLD' ELSE 'MEMORY_THRESHOLD' END AS [EventSubclass_type]
--	,t1.[BatchSeq]
	,t3.[HashID]
	,COUNT(t1.BatchSeq) AS [Nr_Events]
	,LTRIM(REPLACE(REPLACE(t2.[TextData],CHAR(10),''),CHAR(13),'')) AS [TextData]
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblInterestingEvents] t1
LEFT JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t1.[DBID] > 2 
	AND t2.TextData IS NOT NULL
	AND t1.EventID = 60
GROUP BY t1.[DBID],t1.[EventID],t1.[EventSubclass],t2.[TextData],t3.[NormText],t3.[HashID],t4.Name
ORDER BY [DBID], [Nr_Events] DESC
GO

-- Get normalized batches with HASH warnings
-- https://docs.microsoft.com/sql/relational-databases/event-classes/hash-warning-event-class
SELECT DISTINCT t1.[DBID]
	,t1.[EventID]
	,t1.[EventSubclass]
	, CASE WHEN t1.[EventSubclass] = 0 THEN 'Recursion' ELSE 'Bailout' END AS [EventSubclass_type]
--	,t1.[BatchSeq]
	,t3.[HashID]
	,COUNT(t1.BatchSeq) AS [Nr_Events]
	,LTRIM(REPLACE(REPLACE(t2.[TextData],CHAR(10),''),CHAR(13),'')) AS [TextData]
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblInterestingEvents] t1
LEFT JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t1.[DBID] > 2 
	AND t2.TextData IS NOT NULL
	AND t1.EventID = 55
GROUP BY t1.[DBID],t1.[EventID],t1.[EventSubclass],t2.[TextData],t3.[NormText],t3.[HashID],t4.Name
ORDER BY [DBID], [Nr_Events] DESC
GO

-- Get summary of batches with HASH warnings
-- https://docs.microsoft.com/sql/relational-databases/event-classes/hash-warning-event-class
SELECT DISTINCT t1.[DBID]
	, CASE WHEN t1.[EventSubclass] = 0 THEN 'Recursion' ELSE 'Bailout' END AS [EventSubclass_type]
	,COUNT(t1.BatchSeq) AS [Nr_Events]
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblInterestingEvents] t1
LEFT JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t1.[DBID] > 2 
	AND t2.TextData IS NOT NULL
	AND t1.EventID = 55
GROUP BY t1.[DBID],t1.[EventSubclass],t3.[NormText],t4.Name
ORDER BY [DBID], [Nr_Events] DESC
GO

-- Get normalized batches with SORT warnings
-- https://docs.microsoft.com/sql/relational-databases/event-classes/sort-warnings-event-class
SELECT DISTINCT t1.[DBID]
	,t1.[EventID]
	,t1.[EventSubclass]
	, CASE WHEN t1.[EventSubclass] = 1 THEN 'Single pass' ELSE 'Multiple pass' END AS [EventSubclass_type]
--	,t1.[BatchSeq]
	,t3.[HashID]
	,COUNT(t1.BatchSeq) AS [Nr_Events]
	,LTRIM(REPLACE(REPLACE(t2.[TextData],CHAR(10),''),CHAR(13),'')) AS [TextData]
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblInterestingEvents] t1
LEFT JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t1.[DBID] > 2 
	AND t2.TextData IS NOT NULL
	AND t1.EventID = 69
GROUP BY t1.[DBID],t1.[EventID],t1.[EventSubclass],t2.[TextData],t3.[NormText],t3.[HashID],t4.Name
ORDER BY [DBID], [Nr_Events] DESC
GO

-- Get summary of batches with SORT warnings
-- https://docs.microsoft.com/sql/relational-databases/event-classes/sort-warnings-event-class
SELECT DISTINCT t1.[DBID]
	, CASE WHEN t1.[EventSubclass] = 1 THEN 'Single pass' ELSE 'Multiple pass' END AS [EventSubclass_type]
	,COUNT(t1.BatchSeq) AS [Nr_Events]
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblInterestingEvents] t1
LEFT JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t1.[DBID] > 2 
	AND t2.TextData IS NOT NULL
	AND t1.EventID = 69
GROUP BY t1.[DBID],t1.[EventSubclass],t3.[NormText],t4.Name
ORDER BY [DBID], [Nr_Events] DESC
GO

-- Get normalized batches with missing join predicate
-- https://docs.microsoft.com/sql/relational-databases/event-classes/hash-warning-event-class
SELECT DISTINCT t1.[DBID]
    ,t1.[EventID]
--	,t1.[BatchSeq]
	,t3.[HashID]
	,COUNT(t1.BatchSeq) AS [Nr_Events]
	,LTRIM(REPLACE(REPLACE(t2.[TextData],CHAR(10),''),CHAR(13),'')) AS [TextData]
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblInterestingEvents] t1
LEFT JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t1.[DBID] > 2 
	AND t2.TextData IS NOT NULL
	AND t1.EventID = 80
GROUP BY t1.[DBID],t1.[EventID],t1.[EventSubclass],t2.[TextData],t3.[NormText],t3.[HashID],t4.Name
ORDER BY [DBID], [Nr_Events] DESC
GO

-- Get normalized batches with attentions
-- https://docs.microsoft.com/sql/relational-databases/event-classes/attention-event-class
SELECT DISTINCT t1.[DBID]
	,t1.[EventID]
--	,t1.[BatchSeq]
	,t3.[HashID]
	,COUNT(t1.BatchSeq) AS [Nr_Events]
	,LTRIM(REPLACE(REPLACE(t2.[TextData],CHAR(10),''),CHAR(13),'')) AS [TextData]
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
--	,t2.StartTime AS BatchStartTime
--	,t1.StartTime AS AttentionTime
	,AVG(DATEDIFF(ms, t2.StartTime, t1.StartTime)) AS AvgMsToAttention
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblInterestingEvents] t1
LEFT JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t2.TextData IS NOT NULL
	AND t1.EventID = 16
GROUP BY t1.[DBID],t1.[EventID],t1.[EventSubclass],t2.[TextData],t3.[NormText],t3.[HashID],t4.Name--,t1.StartTime,t2.StartTime
ORDER BY [DBID], [Nr_Events] DESC
GO

-- Get normalized batches with auto-stats
SELECT DISTINCT t1.[DBID]
    ,t1.[EventID]
--	,t1.[BatchSeq]
	,t3.[HashID]
	,COUNT(t1.BatchSeq) AS [Nr_Events]
	,LTRIM(REPLACE(REPLACE(t2.[TextData],CHAR(10),''),CHAR(13),'')) AS [TextData]
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblInterestingEvents] t1
LEFT JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t2.TextData IS NOT NULL
	AND t1.EventID = 58
GROUP BY t1.[DBID],t1.[EventID],t1.[EventSubclass],t2.[TextData],t3.[NormText],t3.[HashID],t4.Name
ORDER BY [DBID], [Nr_Events] DESC
GO

-- Get normalized batches with lock escalations
-- https://docs.microsoft.com/sql/relational-databases/event-classes/attention-event-class
SELECT DISTINCT t1.[DBID]
	,t1.[EventID]
--	,t1.[BatchSeq]
	,t3.[HashID]
	,COUNT(t1.BatchSeq) AS [Nr_Events]
	,LTRIM(REPLACE(REPLACE(t2.[TextData],CHAR(10),''),CHAR(13),'')) AS [TextData]
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblInterestingEvents] t1
LEFT JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t2.TextData IS NOT NULL
	AND t1.EventID = 60
GROUP BY t1.[DBID],t1.[EventID],t1.[EventSubclass],t2.[TextData],t3.[NormText],t3.[HashID],t4.Name
ORDER BY [DBID], [Nr_Events] DESC
GO

-- Get normalized batches with OLEDB errors
-- https://docs.microsoft.com/sql/relational-databases/event-classes/oledb-errors-event-class
SELECT DISTINCT t1.[DBID]
	,t1.[EventID]
--	,t1.[BatchSeq]
	,t3.[HashID]
	,t1.[Error]
	,COUNT(t1.BatchSeq) AS [Nr_Events]
	,LTRIM(REPLACE(REPLACE(t2.[TextData],CHAR(10),''),CHAR(13),'')) AS [TextData]
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
	,t4.Name AS [Procedure]
FROM [ReadTrace].[tblInterestingEvents] t1
LEFT JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t2.TextData IS NOT NULL
	AND t1.EventID = 61
GROUP BY t1.[DBID],t1.[EventID],t1.[EventSubclass],t2.[TextData],t3.[NormText],t3.[HashID],t4.Name,t1.[Error]
ORDER BY [DBID], [Nr_Events] DESC
GO

--Get normalized batches with Exceptions
SELECT DISTINCT t1.[DBID]
	,t1.[EventID]
--	,t1.[BatchSeq]
	,t3.[HashID]
	,t1.[Error]
	,COUNT(t1.BatchSeq) AS [Nr_Events]
	,LTRIM(REPLACE(REPLACE(t2.[TextData],CHAR(10),''),CHAR(13),'')) AS [TextData]
	,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
	,t4.Name AS [Procedure]
--	,LEFT(LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')),150) AS [Normalized_TextData_1st150Chars]
	,(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(text,'%.*ls','%'),'%d','%'),'%ls','%'),'%S_MSG','%'),'%S_PGID','%'),'%#016I64x','%'),'%p','%'),'%08x','%'),'%u','%'),'%I64d','%'),'%s','%'),'%ld','%'),'%lx','%'), '%%%', '%') 
	FROM sys.messages WHERE message_id = [Error] AND language_id = 1033) AS [Error_Msg]
FROM [ReadTrace].[tblInterestingEvents] t1
LEFT JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
LEFT JOIN ReadTrace.tblProcedureNames t4 on t3.SpecialProcID = t4.SpecialProcID
WHERE t2.TextData IS NOT NULL
	AND t1.EventID = 33
GROUP BY t1.[DBID],t1.[EventID],t1.[EventSubclass],t2.[TextData],t3.[NormText],t3.[HashID],t4.Name,t1.[Error]
ORDER BY [Nr_Events] DESC
GO

--Get statements with errors 207, 208, 245 and 257
SELECT DISTINCT t1.[DBID]
      ,t1.[TextData]
      ,t1.[ObjectID]
      ,t1.[Error]
      --,t1.[BatchSeq]
	  ,t2.[HashID]
	  ,t2.[TextData]
	  , CASE WHEN t1.TextData LIKE 'Error: 207%' THEN 'Invalid column name'
		WHEN t1.TextData LIKE 'Error: 245%' THEN 'Conversion failed when converting the %ls value to data type %ls.'
		WHEN t1.TextData LIKE 'Error: 208%' THEN 'Invalid object name'
		WHEN t1.TextData LIKE 'Error: 257%' THEN 'Implicit conversion from data type %ls to %ls is not allowed. Use the CONVERT function to run this query.'
		END AS [ErrorType]
FROM [ReadTrace].[tblInterestingEvents] t1
INNER JOIN [ReadTrace].[tblBatches] t2 ON t1.BatchSeq = t2.BatchSeq
WHERE t1.[DBID] > 2 AND (t1.TextData LIKE 'Error: 207%' 
OR t1.TextData LIKE 'Error: 245%' 
OR t1.TextData LIKE 'Error: 208%'
OR t1.TextData LIKE 'Error: 257%')
GO

-- Get batches with Deprecated code
SET NOCOUNT ON;

DECLARE @tblKeywords TABLE (
 	KeywordID int IDENTITY(1,1) PRIMARY KEY,
 	Keyword NVARCHAR(64),	-- the keyword itself
	DeprecatedIn tinyint,
	DiscontinuedIn tinyint,
	Done bit
	);

CREATE TABLE [#FinalResult](
	[DBID] int NOT NULL,
	[HashID] bigint NOT NULL,
	[Nr_Events] int NULL,
	[TextData] NVARCHAR(max) NULL,
	[Normalized_TextData] NVARCHAR(max) NULL,
	[Keyword] NVARCHAR(64)
	);

-- Populate Keywords table
INSERT INTO @tblKeywords (Keyword, DeprecatedIn, DiscontinuedIn, Done)
SELECT 'disk init', NULL, 9, 0 UNION ALL
SELECT 'disk resize', NULL, 9, 0 UNION ALL
SELECT 'for load', NULL, 9, 0 UNION ALL
SELECT 'dbcc dbrepair', NULL, 9, 0 UNION ALL
SELECT 'dbcc newalloc', NULL, 9, 0 UNION ALL
SELECT 'dbcc pintable', NULL, 9, 0 UNION ALL
SELECT 'dbcc unpintable', NULL, 9, 0 UNION ALL
SELECT 'dbcc rowlock', NULL, 9, 0 UNION ALL
SELECT 'dbcc textall', NULL, 9, 0 UNION ALL
SELECT 'dbcc textalloc', NULL, 9, 0 UNION ALL
SELECT '*=', NULL, 9, 0 UNION ALL
SELECT '=*', NULL, 9, 0 UNION ALL
-- Deprecated on SQL Server 2005 and not yet discontinued
SELECT '::', 9, NULL, 0 UNION ALL
SELECT 'setuser', 9, NULL, 0 UNION ALL
SELECT 'sp_helpdevice', 9, NULL, 0 UNION ALL
SELECT 'sp_addtype', 9, NULL, 0 UNION ALL
SELECT 'sp_attach_db', 9, NULL, 0 UNION ALL
SELECT 'sp_attach_single_file_db', 9, NULL, 0 UNION ALL
SELECT 'sp_bindefault', 9, NULL, 0 UNION ALL
SELECT 'sp_unbindefault', 9, NULL, 0 UNION ALL
SELECT 'sp_bindrule', 9, NULL, 0 UNION ALL
SELECT 'sp_unbindrule', 9, NULL, 0 UNION ALL
SELECT 'create default', 9, NULL, 0 UNION ALL
SELECT 'drop default', 9, NULL, 0 UNION ALL
SELECT 'create rule', 9, NULL, 0 UNION ALL
SELECT 'drop rule', 9, NULL, 0 UNION ALL
SELECT 'sp_renamedb', 9, NULL, 0 UNION ALL
SELECT 'sp_resetstatus', 9, NULL, 0 UNION ALL
SELECT 'dbcc dbreindex', 9, NULL, 0 UNION ALL
SELECT 'dbcc indexdefrag', 9, NULL, 0 UNION ALL
SELECT 'dbcc showcontig', 9, NULL, 0 UNION ALL
SELECT 'sp_addextendedproc', 9, NULL, 0 UNION ALL
SELECT 'sp_dropextendedproc', 9, NULL, 0 UNION ALL
SELECT 'sp_helpextendedproc', 9, NULL, 0 UNION ALL
SELECT 'xp_loginconfig', 9, NULL, 0 UNION ALL
SELECT 'sp_fulltext_catalog', 9, NULL, 0 UNION ALL
SELECT 'sp_fulltext_table', 9, NULL, 0 UNION ALL
SELECT 'sp_fulltext_column', 9, NULL, 0 UNION ALL
SELECT 'sp_fulltext_database', 9, NULL, 0 UNION ALL
SELECT 'sp_help_fulltext_tables', 9, NULL, 0 UNION ALL
SELECT 'sp_help_fulltext_columns', 9, NULL, 0 UNION ALL
SELECT 'sp_help_fulltext_catalogs', 9, NULL, 0 UNION ALL
SELECT 'sp_help_fulltext_tables_cursor', 9, NULL, 0 UNION ALL
SELECT 'sp_help_fulltext_columns_cursor', 9, NULL, 0 UNION ALL
SELECT 'sp_help_fulltext_catalogs_cursor', 9, NULL, 0 UNION ALL
SELECT 'fn_get_sql', 9, NULL, 0 UNION ALL
SELECT 'sp_indexoption', 9, NULL, 0 UNION ALL
SELECT 'sp_lock', 9, NULL, 0 UNION ALL
SELECT 'indexkey_property', 9, NULL, 0 UNION ALL
SELECT 'file_id', 9, NULL, 0 UNION ALL
SELECT 'sp_certify_removable', 9, NULL, 0 UNION ALL
SELECT 'sp_create_removable', 9, NULL, 0 UNION ALL
SELECT 'sp_dbremove', 9, NULL, 0 UNION ALL
SELECT 'sp_addapprole', 9, NULL, 0 UNION ALL
SELECT 'sp_dropapprole', 9, NULL, 0 UNION ALL
SELECT 'sp_addlogin', 9, NULL, 0 UNION ALL
SELECT 'sp_droplogin', 9, NULL, 0 UNION ALL
SELECT 'sp_adduser', 9, NULL, 0 UNION ALL
SELECT 'sp_dropuser', 9, NULL, 0 UNION ALL
SELECT 'sp_grantdbaccess', 9, NULL, 0 UNION ALL
SELECT 'sp_revokedbaccess', 9, NULL, 0 UNION ALL
SELECT 'sp_addrole', 9, NULL, 0 UNION ALL
SELECT 'sp_droprole', 9, NULL, 0 UNION ALL
SELECT 'sp_approlepassword', 9, NULL, 0 UNION ALL
SELECT 'sp_password', 9, NULL, 0 UNION ALL
SELECT 'sp_changeobjectowner', 9, NULL, 0 UNION ALL
SELECT 'sp_defaultdb', 9, NULL, 0 UNION ALL
SELECT 'sp_defaultlanguage', 9, NULL, 0 UNION ALL
SELECT 'sp_denylogin', 9, NULL, 0 UNION ALL
SELECT 'sp_grantlogin', 9, NULL, 0 UNION ALL
SELECT 'sp_revokelogin', 9, NULL, 0 UNION ALL
SELECT 'user_id', 9, NULL, 0 UNION ALL
SELECT 'sp_srvrolepermission', 9, NULL, 0 UNION ALL
SELECT 'sp_dbfixedrolepermission', 9, NULL, 0 UNION ALL
SELECT 'text', 9, NULL, 0 UNION ALL
SELECT 'ntext', 9, NULL, 0 UNION ALL
SELECT 'image', 9, NULL, 0 UNION ALL
SELECT 'textptrSELECT ', 9, NULL, 0 UNION ALL
SELECT 'textvalidSELECT ', 9, NULL, 0 UNION ALL
-- Discontinued on SQL Server 2008
SELECT 'sp_addalias', 9, 10, 0 UNION ALL
SELECT 'no_log', 9, 10, 0 UNION ALL
SELECT 'truncate_only', 9, 10, 0 UNION ALL
SELECT 'backup transaction', 9, 10, 0 UNION ALL
SELECT 'dbcc concurrencyviolation', 9, 10, 0 UNION ALL
SELECT 'sp_addgroup', 9, 10, 0 UNION ALL
SELECT 'sp_changegroup', 9, 10, 0 UNION ALL
SELECT 'sp_dropgroup', 9, 10, 0 UNION ALL
SELECT 'sp_helpgroup', 9, 10, 0 UNION ALL
SELECT 'sp_makewebtask', NULL, 10, 0 UNION ALL
SELECT 'sp_dropwebtask', NULL, 10, 0 UNION ALL
SELECT 'sp_runwebtask', NULL, 10, 0 UNION ALL
SELECT 'sp_enumcodepages', NULL, 10, 0 UNION ALL
SELECT 'dump', 9, 10, 0 UNION ALL
SELECT 'load', 9, 10, 0 UNION ALL
-- Undocumented system stored procedures are removed from sql server:
SELECT 'sp_articlesynctranprocs', NULL, 10, 0 UNION ALL
SELECT 'sp_diskdefault', NULL, 10, 0 UNION ALL
SELECT 'sp_eventlog', NULL, 10, 0 UNION ALL
SELECT 'sp_getmbcscharlen', NULL, 10, 0 UNION ALL
SELECT 'sp_helplog', NULL, 10, 0 UNION ALL
SELECT 'sp_helpsql', NULL, 10, 0 UNION ALL
SELECT 'sp_ismbcsleadbyte', NULL, 10, 0 UNION ALL
SELECT 'sp_lock2', NULL, 10, 0 UNION ALL
SELECT 'sp_msget_current_activity', NULL, 10, 0 UNION ALL
SELECT 'sp_msset_current_activity', NULL, 10, 0 UNION ALL
SELECT 'sp_msobjessearch', NULL, 10, 0 UNION ALL
SELECT 'xp_enum_activescriptengines', NULL, 10, 0 UNION ALL
SELECT 'xp_eventlog', NULL, 10, 0 UNION ALL
SELECT 'xp_getadmingroupname', NULL, 10, 0 UNION ALL
SELECT 'xp_getfiledetails', NULL, 10, 0 UNION ALL
SELECT 'xp_getlocalsystemaccountname', NULL, 10, 0 UNION ALL
SELECT 'xp_isntadmin', NULL, 10, 0 UNION ALL
SELECT 'xp_mslocalsystem', NULL, 10, 0 UNION ALL
SELECT 'xp_msnt2000', NULL, 10, 0 UNION ALL
SELECT 'xp_msplatform', NULL, 10, 0 UNION ALL
SELECT 'xp_setsecurity', NULL, 10, 0 UNION ALL
SELECT 'xp_varbintohexstr', NULL, 10, 0 UNION ALL
-- Undocumented system tables are removed from sql server:
SELECT 'spt_datatype_info', NULL, 10, 0 UNION ALL
SELECT 'spt_datatype_info_ext', NULL, 10, 0 UNION ALL
SELECT 'spt_provider_types', NULL, 10, 0 UNION ALL
SELECT 'spt_server_info', NULL, 10, 0 UNION ALL
SELECT 'spt_values', NULL, 10, 0 UNION ALL
SELECT 'sysfulltextnotify ', NULL, 10, 0 UNION ALL
SELECT 'syslocks', NULL, 10, 0 UNION ALL
SELECT 'sysproperties', NULL, 10, 0 UNION ALL
SELECT 'sysprotects_aux', NULL, 10, 0 UNION ALL
SELECT 'sysprotects_view', NULL, 10, 0 UNION ALL
SELECT 'sysremote_catalogs', NULL, 10, 0 UNION ALL
SELECT 'sysremote_column_privileges', NULL, 10, 0 UNION ALL
SELECT 'sysremote_columns', NULL, 10, 0 UNION ALL
SELECT 'sysremote_foreign_keys', NULL, 10, 0 UNION ALL
SELECT 'sysremote_indexes', NULL, 10, 0 UNION ALL
SELECT 'sysremote_primary_keys', NULL, 10, 0 UNION ALL
SELECT 'sysremote_provider_types', NULL, 10, 0 UNION ALL
SELECT 'sysremote_schemata', NULL, 10, 0 UNION ALL
SELECT 'sysremote_statistics', NULL, 10, 0 UNION ALL
SELECT 'sysremote_table_privileges', NULL, 10, 0 UNION ALL
SELECT 'sysremote_tables', NULL, 10, 0 UNION ALL
SELECT 'sysremote_views', NULL, 10, 0 UNION ALL
SELECT 'syssegments', NULL, 10, 0 UNION ALL
SELECT 'sysxlogins', NULL, 10, 0 UNION ALL
-- Deprecated on SQL Server 2008 and not yet discontinued
SELECT 'sp_addremotelogin', 10, NULL, 0 UNION ALL
SELECT 'sp_dropremotelogin', 10, NULL, 0 UNION ALL
SELECT 'sp_helpremotelogin', 10, NULL, 0 UNION ALL
SELECT 'sp_remoteoption', 10, NULL, 0 UNION ALL
SELECT '@@remserver', 10, NULL, 0 UNION ALL
SELECT 'remote_proc_transactions', 10, NULL, 0 UNION ALL
SELECT 'sp_addumpdevice', 10, NULL, 0 UNION ALL
SELECT 'xp_grantlogin', 10, NULL, 0 UNION ALL
SELECT 'xp_revokelogin', 10, NULL, 0 UNION ALL
SELECT 'grant all', 10, NULL, 0 UNION ALL
SELECT 'deny all', 10, NULL, 0 UNION ALL
SELECT 'revoke all', 10, NULL, 0 UNION ALL
SELECT 'fn_virtualservernodes', 10, NULL, 0 UNION ALL
SELECT 'fn_servershareddrives', 10, NULL, 0 UNION ALL
SELECT 'writetext', 10, NULL, 0 UNION ALL
SELECT 'updatetext', 10, NULL, 0 UNION ALL
SELECT 'readtext', 10, NULL, 0 UNION ALL
-- Discontinued on SQL Server 2012
SELECT 'dbo_only', 9, 11, 0 UNION ALL -- on restore statements
SELECT 'mediapassword', 9, 11, 0 UNION ALL -- on backup statements
SELECT 'password', 9, 11, 0 UNION ALL -- on backup statements except for media
SELECT 'with append', 10, 11, 0 UNION ALL -- on triggers
SELECT 'sp_dboption', 9, 11, 0 UNION ALL
SELECT 'databaseproperty', 9, 11, 0 UNION ALL
SELECT 'fastfirstrow', 10, 11, 0 UNION ALL
SELECT 'sp_addserver', 10, 11, 0 UNION ALL -- for linked servers
SELECT 'sp_dropalias', 9, 11, 0 UNION ALL
SELECT 'disable_def_cnst_chk', 10, 11, 0 UNION ALL
SELECT 'sp_activedirectory_obj', NULL, 11, 0 UNION ALL
SELECT 'sp_activedirectory_scp', NULL, 11, 0 UNION ALL
SELECT 'sp_activedirectory_start', NULL, 11, 0 UNION ALL
-- Deprecated on SQL Server 2012 and not yet discontinued
SELECT 'compute by', NULL, 11, 0 UNION ALL
SELECT 'compute', NULL, 11, 0 UNION ALL
SELECT 'sp_change_users_login', 11, NULL, 0 UNION ALL
SELECT 'sp_depends', 11, NULL, 0 UNION ALL
SELECT 'sp_getbindtoken', 11, NULL, 0 UNION ALL
SELECT 'sp_bindsession', 11, NULL, 0 UNION ALL
SELECT 'fmtonly', 11, NULL, 0 UNION ALL
SELECT 'sp_db_increased_partitions', 11, NULL, 0

DECLARE @i int, @Keyword NVARCHAR(64)
WHILE (SELECT COUNT(*) FROM @tblKeywords WHERE Done = 0) > 0
BEGIN
	SELECT TOP 1 @i = KeywordID, @Keyword = '%' + Keyword + '%' FROM @tblKeywords WHERE Done = 0

	INSERT INTO #FinalResult
	SELECT DISTINCT t1.[DBID]
	  ,t2.[HashID]
	  ,COUNT(t2.BatchSeq) AS [Nr_Events]
	  ,LTRIM(REPLACE(REPLACE(t2.[TextData],CHAR(10),''),CHAR(13),'')) AS [TextData]
	  ,LTRIM(REPLACE(REPLACE(t3.[NormText],CHAR(10),''),CHAR(13),'')) AS [Normalized_TextData]
	  ,@Keyword AS Search_Keyword
	FROM [ReadTrace].[tblBatchPartialAggs] t1
	INNER JOIN [ReadTrace].[tblBatches] t2 ON t1.HashID = t2.HashID
	INNER JOIN [ReadTrace].[tblUniqueBatches] t3 ON t2.HashID = t3.HashID
	WHERE t1.[DBID] > 2 
		AND t2.TextData LIKE @Keyword
	GROUP BY t1.[DBID],t2.[TextData],t2.[HashID],t3.[NormText]

	UPDATE @tblKeywords
	SET Done = 1
	WHERE KeywordID = @i
END

SELECT * FROM #FinalResult
ORDER BY [DBID], [Nr_Events] DESC

DROP TABLE #FinalResult
GO
