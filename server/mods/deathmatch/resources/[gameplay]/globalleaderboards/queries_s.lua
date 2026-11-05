QUERY_SELECT_MAIN = [[
	SELECT * FROM globalLeaderboards_players ORDER BY totalTime ASC
]]

QUERY_SELECT_MAPLIST = [[
	SELECT
		m.mapName,
		m.topTime,
		m.topTimeDate,
		m.avgTime,
		m.playerCount,
		r.bestTime AS yourTime,
		r.dateRecorded AS yourTimeDate,
		r.rank AS yourRank
	FROM globalLeaderboards_maps m
	LEFT JOIN globalLeaderboards_players p
		ON p.playerName = ?
	LEFT JOIN globalLeaderboards_rankings r
		ON r.mapId = m.id AND r.playerId = p.id
	WHERE m.blacklisted = 0 AND m.gone = 0 AND m.negativeTime = 0 AND m.unscored = 0
	ORDER BY m.mapName ASC
]]

QUERY_SELECT_PLAYER = [[
	SELECT
		m.mapName,
		m.fileName,
		r.bestTime,
		r.rank,
		m.playerCount AS totalFinishers,
		m.topTime AS topTime,
		r.dateRecorded
	FROM globalLeaderboards_players p
	JOIN globalLeaderboards_rankings r ON p.id = r.playerId
	JOIN globalLeaderboards_maps m ON m.id = r.mapId
	WHERE p.playerName = ?
	AND r.valid = 1
	ORDER BY m.mapName ASC;
]]

QUERY_SELECT_MAP = [[
	SELECT
		playerName,
		dateRecorded,
		MIN(time) AS bestTime
	FROM maptimes
	WHERE mapName = ?
	GROUP BY playerName
	ORDER BY bestTime;
]]

-- ------------------------------------------
-- ------------------------------------------
-- Resource start , table creation population
-- ------------------------------------------
-- ------------------------------------------

QUERY_MAPS_DROP = [[
	DROP TABLE IF EXISTS globalLeaderboards_maps;
]]

QUERY_MAPS_CREATE = [[
	CREATE TABLE globalLeaderboards_maps (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		mapName TEXT UNIQUE NOT NULL,
		fileName TEXT UNIQUE,
		timeLimit INTEGER,
		playerCount INTEGER DEFAULT 0,
		topTime INTEGER DEFAULT NULL,
		topTimeDate INTEGER DEFAULT NULL,
		avgTime INTEGER DEFAULT NULL,
		unscored BOOLEAN DEFAULT FALSE,
		negativeTime BOOLEAN DEFAULT FALSE,
		gone BOOLEAN DEFAULT FALSE,
		blacklisted BOOLEAN DEFAULT FALSE
	);
]]

QUERY_MAPS_POPULATE = [[
	INSERT OR IGNORE INTO globalLeaderboards_maps (mapName)
	SELECT DISTINCT CAST(mapName AS TEXT)
	FROM maptimes
	ORDER BY mapName
]]

QUERY_MAPS_INDEX = [[
	CREATE INDEX idx_maps_mapName ON globalLeaderboards_maps(mapName);
]]

QUERY_MAPS_UPDATE_RECORD_STATS = [[
	WITH MapStats AS (
		SELECT
			r.mapId,
			MIN(r.bestTime) AS topTime,
			CAST(AVG(r.bestTime) AS INTEGER) AS avgTime,
			COUNT(DISTINCT r.playerId) AS playerCount,
			MAX(CASE WHEN r.bestTime < 0 THEN 1 ELSE 0 END) AS hasNegativeTime,
			(
				SELECT MIN(dateRecorded)
				FROM globalLeaderboards_rankings rr
				WHERE rr.mapId = r.mapId AND rr.bestTime = MIN(r.bestTime)
			) AS topTimeDate
		FROM globalLeaderboards_rankings r
		GROUP BY r.mapId
	)
	UPDATE globalLeaderboards_maps
	SET
		topTime = s.topTime,
		topTimeDate = s.topTimeDate,
		avgTime = s.avgTime,
		playerCount = s.playerCount,
		negativeTime = s.hasNegativeTime
	FROM MapStats s
	WHERE globalLeaderboards_maps.id = s.mapId;
]]

QUERY_MAPS_INSERT = [[
	INSERT INTO globalLeaderboards_maps (
		mapName, fileName, timeLimit, unscored, blacklisted
	)
	VALUES (
		?, ?, ?, 1, ?
	)
	ON CONFLICT(mapName) DO UPDATE SET
		fileName=excluded.fileName,
		timeLimit=excluded.timeLimit,
		unscored=0,
		blacklisted=excluded.blacklisted;
]]

QUERY_MAPS_HANDLE_GONERS = [[
	UPDATE globalLeaderboards_maps
	SET gone = 1
	WHERE (fileName IS NULL)
	AND gone = 0
]]

-------------
-- Players --
-------------

QUERY_PLAYERS_DROP = [[
	DROP TABLE IF EXISTS globalLeaderboards_players;
]]

QUERY_PLAYERS_CREATE = [[
	CREATE TABLE globalLeaderboards_players (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		playerName TEXT UNIQUE NOT NULL,
		playerSerial TEXT UNIQUE,
		top1 INTEGER DEFAULT 0,
		top2 INTEGER DEFAULT 0,
		top3 INTEGER DEFAULT 0,
		top11 INTEGER DEFAULT 0,
		ranked INTEGER DEFAULT 0,
		unranked INTEGER DEFAULT 0,
		totalRankScore INTEGER DEFAULT 0,
		totalTime INTEGER DEFAULT 0
	);
]]

QUERY_PLAYERS_POPULATE = [[
	INSERT OR IGNORE INTO globalLeaderboards_players (playerName)
	SELECT DISTINCT CAST(playerName AS TEXT) || ''
	FROM maptimes
	ORDER BY playerName;
]]

QUERY_PLAYERS_INDEX = [[
	CREATE INDEX idx_players_playerName ON globalLeaderboards_players(playerName);
]]

QUERY_PLAYERS_UPDATE_STATS = [[
	WITH
	ValidMaps AS (
		SELECT id, timeLimit, playerCount
		FROM globalLeaderboards_maps
		WHERE blacklisted = 0 AND gone = 0 and negativeTime = 0 AND unscored = 0
	),
	PlayerMapRanks AS (
		SELECT
			p.id AS playerId,
			m.id AS mapId,
			COALESCE(r.rank, m.playerCount + 1) AS pretendRank,
			COALESCE(r.bestTime, m.timeLimit) AS pretendTime,
			r.rank AS realRank,
			m.playerCount
		FROM globalLeaderboards_players p
		CROSS JOIN ValidMaps m
		LEFT JOIN globalLeaderboards_rankings r
			ON r.playerId = p.id AND r.mapId = m.id
	),
	PlayerStats AS (
		SELECT
			pmr.playerId,
			SUM(CASE WHEN pretendRank = 1 AND playerCount >= 1 THEN 1 ELSE 0 END) AS top1,
			SUM(CASE WHEN pretendRank <= 2 AND playerCount >= 2 THEN 1 ELSE 0 END) AS top2,
			SUM(CASE WHEN pretendRank <= 3 AND playerCount >= 3 THEN 1 ELSE 0 END) AS top3,
			SUM(CASE WHEN pretendRank <= 11 AND playerCount >= pretendRank THEN 1 ELSE 0 END) AS top11,
			COUNT(*) AS totalRankedMaps,
			SUM(CASE WHEN realRank IS NOT NULL THEN 1 ELSE 0 END) AS rankedCount,
			SUM(pretendRank) AS totalRankScore,
			SUM(pretendTime) AS totalTime
		FROM PlayerMapRanks pmr
		GROUP BY pmr.playerId
	)
	UPDATE globalLeaderboards_players
	SET
		top1 = ps.top1,
		top2 = ps.top2,
		top3 = ps.top3,
		top11 = ps.top11,
		ranked = ps.rankedCount,
		unranked = ps.totalRankedMaps - ps.rankedCount,
		totalRankScore = ps.totalRankScore,
		totalTime = ps.totalTime
	FROM PlayerStats ps
	WHERE ps.playerId = globalLeaderboards_players.id;
]]

------------
-- Scores --
------------

QUERY_RANKINGS_DROP = [[
	DROP TABLE IF EXISTS globalLeaderboards_rankings;
]]

QUERY_RANKINGS_CREATE = [[
	CREATE TABLE globalLeaderboards_rankings (
		mapId INTEGER NOT NULL,
		playerId INTEGER NOT NULL,
		bestTime INTEGER NOT NULL,
		dateRecorded INTEGER NOT NULL,
		rank INTEGER NOT NULL,
		valid BOOLEAN DEFAULT FALSE,
		FOREIGN KEY (mapId) REFERENCES globalLeaderboards_maps(id),
		FOREIGN KEY (playerId) REFERENCES globalLeaderboards_players(id)
	);
]]

QUERY_RANKINGS_POPULATE = [[
	WITH ValidMaps AS (
		SELECT m.mapName
		FROM maptimes m
		INNER JOIN globalLeaderboards_maps l ON m.mapName = l.mapName
		GROUP BY m.mapName
	),
	BestTimes AS (
		SELECT
			mapName,
			CAST(playerName AS TEXT) || '' AS playerName,
			MIN(time) AS bestTime,
			MAX(dateRecorded) AS dateRecorded
		FROM maptimes
		WHERE mapName IN (SELECT mapName FROM ValidMaps)
		GROUP BY mapName, playerName
	),
	Ranked AS (
		SELECT
			mapName,
			CAST(playerName AS TEXT) || '' AS playerName,
			bestTime,
			dateRecorded,
			RANK() OVER (PARTITION BY mapName ORDER BY bestTime ASC) AS rank
		FROM BestTimes
	)
	INSERT INTO globalLeaderboards_rankings (mapId, playerId, bestTime, dateRecorded, rank)
	SELECT
		l.id AS mapId,
		p.id AS playerId,
		r.bestTime,
		r.dateRecorded,
		r.rank
	FROM Ranked r
	JOIN globalLeaderboards_maps l ON r.mapName = l.mapName
	JOIN globalLeaderboards_players p ON r.playerName = p.playerName;
]]

QUERY_RANKINGS_VALIDATE = [[
	UPDATE globalLeaderboards_rankings
	SET valid = (
		SELECT CASE WHEN
			m.blacklisted = 0 AND m.gone = 0 AND m.negativeTime = 0
			THEN 1 ELSE 0
		END
		FROM globalLeaderboards_maps m
		WHERE m.id = globalLeaderboards_rankings.mapId
	);
]]


QUERY_RANKINGS_INDEX_M = [[
	CREATE INDEX idx_rankings_mapId ON globalLeaderboards_rankings(mapId);
]]

QUERY_RANKINGS_INDEX_P = [[
	CREATE INDEX idx_rankings_playerId ON globalLeaderboards_rankings(playerId);
]]

QUERY_RANKINGS_INDEX_MP = [[
	CREATE INDEX idx_rankings_mapId_playerId ON globalLeaderboards_rankings(mapId, playerId);
]]

QUERY_RANKINGS_INDEX_MT = [[
	CREATE INDEX idx_rankings_mapId_bestTime ON globalLeaderboards_rankings(mapId, bestTime);
]]

QUERY_RANKINGS_INDEX_PT = [[
	CREATE INDEX idx_rankings_playerId_bestTime ON globalLeaderboards_rankings(playerId, bestTime);
]]


------------------
-- Fake players --
------------------

QUERY_WORST_PLAYER_INSERT = [[
	INSERT OR IGNORE INTO globalLeaderboards_players (playerName)
	VALUES ('<Rest of the World>');
]]

QUERY_WORST_PLAYER_RANK = [[
	INSERT INTO globalLeaderboards_rankings (
		mapId, playerId, bestTime, dateRecorded, rank, valid
	)
	SELECT
		m.id,
		p.id,
		COALESCE(m.timeLimit, 86400000),
		0,
		MAX(r.rank) + 1,
		m.blacklisted = 0 AND m.gone = 0 AND m.negativeTime = 0 AND m.unscored = 0
	FROM globalLeaderboards_maps m
	JOIN globalLeaderboards_players p ON p.playerName = '<Rest of the World>'
	JOIN globalLeaderboards_rankings r ON r.mapId = m.id
	GROUP BY m.id
]]

QUERY_WORST_PLAYER_STATS = [[
	UPDATE globalLeaderboards_players
	SET
		top1 = 0,
		top2 = 0,
		top3 = 0,
		top11 = 0,
		ranked = 0,
		unranked = (
			SELECT COUNT(DISTINCT mapId)
			FROM globalLeaderboards_rankings
			WHERE valid = 1
		),
		totalRankScore = (
			SELECT SUM(rank)
			FROM globalLeaderboards_rankings
			WHERE valid = 1
			AND playerId = globalLeaderboards_players.id
		),
		totalTime = (
			SELECT SUM(bestTime)
			FROM globalLeaderboards_rankings
			WHERE valid = 1
			AND playerId = globalLeaderboards_players.id
		)
	WHERE playerName = '<Rest of the World>';
]]

QUERY_BEST_PLAYER_INSERT = [[
	INSERT OR IGNORE INTO globalLeaderboards_players (playerName)
	VALUES ('<Community Sum of Bests>');
]]

QUERY_BEST_PLAYER_RANK = [[
	INSERT INTO globalLeaderboards_rankings (
		mapId, playerId, bestTime, dateRecorded, rank, valid
	)
	SELECT
		r.mapId,
		p.id,
		r.bestTime,
		0,
		0,
		m.blacklisted = 0 AND m.gone = 0 AND m.negativeTime = 0 AND m.unscored = 0
	FROM globalLeaderboards_rankings r
	JOIN globalLeaderboards_players p ON p.playerName = '<Community Sum of Bests>'
	JOIN globalLeaderboards_maps m ON m.id = r.mapId
	WHERE rank = 1;
]]

QUERY_BEST_PLAYER_STATS = [[
	WITH MapCount AS (
		SELECT COUNT(DISTINCT mapId) AS total_maps
		FROM globalLeaderboards_rankings
		WHERE valid = 1
	)
	UPDATE globalLeaderboards_players
	SET
		top1 = (SELECT total_maps FROM MapCount),
		top2 = (SELECT total_maps FROM MapCount),
		top3 = (SELECT total_maps FROM MapCount),
		top11 = (SELECT total_maps FROM MapCount),
		ranked = (SELECT total_maps FROM MapCount),
		unranked = 0,
		totalRankScore = (SELECT total_maps FROM MapCount),
		totalTime = (
			SELECT SUM(bestTime)
			FROM globalLeaderboards_rankings
			WHERE valid = 1
			AND playerId = globalLeaderboards_players.id
		)
	WHERE playerName = '<Community Sum of Bests>';
]]
