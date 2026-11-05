function getAchievementPosByID(ID) -- in the category
	for _, v in pairs(achievementsList) do
		for i, contents in pairs (v) do
			if ID == contents.ID then
				return i
			end
		end
	end
end

-- Function returns achievement from achievementsList by its ID
-- ID type is a string
function getAchievementByID(achievementID)
	-- Find
	for k, v in pairs(achievementsList) do
		for _, contents in pairs (v) do
			if contents.ID == achievementID then
				return contents
			end
		end
	end
	return false
end

-- Function returns achievement from achievementsList by its group and pos in the table
-- Used in visual_c.lua
function getAchievementByGroupAndPos(group, pos)
	-- Find
	for k, v in pairs(achievementsList) do
		if k == group then
			for ID, contents in pairs (v) do
				if ID == pos then
					return contents
				end
			end
		end
	end
	return false
end

-- Function returns achievement ID from achievementsList by its group and pos in the table
-- Used in visual_c.lua
function getAchievementIDByGroupAndPos(group, pos)
	-- Find
	for k, v in pairs(achievementsList) do
		if k == group then
			for _, contents in pairs (v) do
				if _ == pos then
					return contents.ID
				end
			end
		end
	end
	return false
end

local _sort_core = {}
_sort_core.max_chunk_size = 24

function _sort_core.insertion_sort_impl( array, first, last, less )
	for i = first + 1, last do
		local k = first
		local v = array[i]
		for j = i, first + 1, -1 do
			if less( v, array[j-1] ) then
				array[j] = array[j-1]
			else
				k = j
				break
			end
		end
		array[k] = v
	end
end

function _sort_core.merge( array, workspace, low, middle, high, less )
	local i, j, k
	i = 1
	-- copy first half of array to auxiliary array
	for j = low, middle do
		workspace[ i ] = array[ j ]
		i = i + 1
	end
	-- sieve through
	i = 1
	j = middle + 1
	k = low
	while true do
		if (k >= j) or (j > high) then
			break
		end
		if less( array[ j ], workspace[ i ] )  then
			array[ k ] = array[ j ]
			j = j + 1
		else
			array[ k ] = workspace[ i ]
			i = i + 1
		end
		k = k + 1
	end
	-- copy back any remaining elements of first half
	for k = k, j-1 do
		array[ k ] = workspace[ i ]
		i = i + 1
	end
end

function _sort_core.merge_sort_impl(array, workspace, low, high, less)
	if high - low <= _sort_core.max_chunk_size then
		_sort_core.insertion_sort_impl( array, low, high, less )
	else
		local middle = math.floor((low + high) / 2)
		_sort_core.merge_sort_impl( array, workspace, low, middle, less )
		_sort_core.merge_sort_impl( array, workspace, middle + 1, high, less )
		_sort_core.merge( array, workspace, low, middle, high, less )
	end
end

function _sort_core.sort_setup(array, less)
	local n = #array
	local trivial = false
	--trivial cases; empty or 1 element
	if n <= 1 then
		trivial = true
	else
		--default less
		less = less or function (a, b)
			return a < b
		end
		--check less
		if less(array[1], array[1]) then
		  error("invalid order function for sorting")
		end
	end
	--setup complete
	return trivial, n, less
end

function table.stable_sort(array, less)
	--setup
	local trivial, n, less = _sort_core.sort_setup(array, less)
	if not trivial then
		local workspace = {}
		workspace[math.floor((n + 1) / 2)] = array[1]
		_sort_core.merge_sort_impl(array, workspace, 1, n, less)
	end
	return array
end

function sortAchievements()
	-- sorting of the list
	for i, v in pairs(achievementsList) do
		if v[1].maps then
			-- sort
			achievementsList[i] = table.stable_sort(achievementsList[i], function(a, b)
				if a.maps and b.maps then
					if a.maps[1] < b.maps[1] then
						return true
					else return false end
				end
			end )
		end
	end
end
