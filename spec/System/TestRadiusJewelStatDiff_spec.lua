-- Helper: BFS from class start to find and allocate path to nearest jewel socket
local function allocatePathToSocket(spec)
	local classStart
	for _, node in pairs(spec.allocNodes) do
		if node.type == "ClassStart" then
			classStart = node
			break
		end
	end
	if not classStart then return nil end

	local queue = { classStart }
	local visited = { [classStart.id] = true }
	local parent = { }
	local targetSocket
	local head = 1

	while head <= #queue do
		local current = queue[head]
		head = head + 1

		if current.isJewelSocket then
			targetSocket = current
			break
		end

		for _, linked in ipairs(current.linked) do
			if not visited[linked.id] and linked.type ~= "Mastery" and linked.type ~= "AscendClassStart" then
				visited[linked.id] = true
				parent[linked.id] = current
				queue[#queue + 1] = linked
			end
		end
	end

	if not targetSocket then return nil end

	-- Trace path back and allocate all nodes
	local current = targetSocket
	while current do
		current.alloc = true
		spec.allocNodes[current.id] = current
		current = parent[current.id]
	end

	return targetSocket
end

-- Helper: find allocated non-socket non-keystone nodes in a socket's radius
local function findAllocatedNodesInRadius(spec, socketNode, radiusIndex)
	local result = { }
	local inRadius = socketNode.nodesInRadius and socketNode.nodesInRadius[radiusIndex]
	for nodeId in pairs(inRadius or { }) do
		local node = spec.nodes[nodeId]
		if node and node.alloc and node.type ~= "Socket" and node.type ~= "Keystone"
		and node.type ~= "ClassStart" and node.type ~= "AscendClassStart" then
			result[#result + 1] = node
		end
	end
	return result
end

-- Helper: equip Thread of Hope in a socket (no LUT needed)
local function equipThreadOfHope(socketNode)
	local item = new("Item", "Rarity: UNIQUE\n" ..
		"Thread of Hope\n" ..
		"Crimson Jewel\n" ..
		"Variant: Small Ring\n" ..
		"Variant: Medium Ring\n" ..
		"Variant: Large Ring\n" ..
		"Variant: Very Large Ring\n" ..
		"Variant: Massive Ring\n" ..
		"Selected Variant: 3\n" ..
		"Radius: Large\n" ..
		"Implicits: 0\n" ..
		"Only affects Passives in Large Ring\n" ..
		"Passives in Radius can be Allocated without being connected to your Tree\n" ..
		"-20% to all Elemental Resistances\n")
	build.itemsTab:AddItem(item, true)
	-- Set jewels directly to avoid triggering BuildClusterJewelGraphs
	build.spec.jewels[socketNode.id] = item.id
	local slot = build.itemsTab.sockets[socketNode.id]
	if slot then
		slot.selItemId = item.id
	end
	return item
end

describe("TestRadiusJewelStatDiff", function()
	before_each(function()
		newBuild()
	end)

	teardown(function() end)

	it("Lethal Pride item parses conqueredBy correctly", function()
		local item = new("Item", "Rarity: UNIQUE\n" ..
			"Lethal Pride\n" ..
			"Timeless Jewel\n" ..
			"League: Legion\n" ..
			"Limited to: 1 Historic\n" ..
			"Variant: Kaom (Strength of Blood)\n" ..
			"Variant: Rakiata (Tempered by War)\n" ..
			"Variant: Akoya (Chainbreaker)\n" ..
			"Selected Variant: 1\n" ..
			"Radius: Large\n" ..
			"Implicits: 0\n" ..
			"Commanded leadership over 10000 warriors under Kaom\n" ..
			"Passives in radius are Conquered by the Karui\n" ..
			"Historic\n")
		build.itemsTab:AddItem(item, true)

		assert.is_truthy(item.jewelData, "Item should have jewelData")
		assert.is_truthy(item.jewelData.conqueredBy, "Item should have conqueredBy")
		assert.are.equals(10000, item.jewelData.conqueredBy.id)
		assert.are.equals("karui", item.jewelData.conqueredBy.conqueror.type)
		assert.is_truthy(item.jewelRadiusIndex, "Item should have jewelRadiusIndex")
	end)

	it("Thread of Hope item parses intuitiveLeapLike correctly", function()
		local item = new("Item", "Rarity: UNIQUE\n" ..
			"Thread of Hope\n" ..
			"Crimson Jewel\n" ..
			"Variant: Small Ring\n" ..
			"Variant: Medium Ring\n" ..
			"Variant: Large Ring\n" ..
			"Variant: Very Large Ring\n" ..
			"Variant: Massive Ring\n" ..
			"Selected Variant: 3\n" ..
			"Radius: Large\n" ..
			"Implicits: 0\n" ..
			"Only affects Passives in Large Ring\n" ..
			"Passives in Radius can be Allocated without being connected to your Tree\n" ..
			"-20% to all Elemental Resistances\n")
		build.itemsTab:AddItem(item, true)

		assert.is_truthy(item.jewelData, "Item should have jewelData")
		assert.is_truthy(item.jewelData.intuitiveLeapLike, "Item should have intuitiveLeapLike")
		assert.is_truthy(item.jewelRadiusIndex, "Item should have jewelRadiusIndex")
	end)

	it("calcFunc removeNodes/addNodes changes output for allocated nodes", function()
		local spec = build.spec

		-- Allocate path to nearest jewel socket
		local socketNode = allocatePathToSocket(spec)
		spec:BuildAllDependsAndPaths()
		runCallback("OnFrame")
		assert.is_truthy(socketNode, "Should find a jewel socket")

		-- Find allocated nodes in the socket's large radius (index 3)
		local nodesInRadius = findAllocatedNodesInRadius(spec, spec.nodes[socketNode.id], 3)
		assert.is_true(#nodesInRadius > 0, "Should have allocated nodes in radius")

		-- Get calculator
		local calcFunc, calcBase = build.calcsTab:GetMiscCalculator(build)

		-- Test removeNodes: removing an allocated node should produce valid output
		local testNode = nodesInRadius[1]
		local output = calcFunc({ removeNodes = { [testNode] = true } })
		assert.is_truthy(output, "calcFunc with removeNodes should return output")

		-- Test addNodes with original tree node version
		local origNode = spec.tree.nodes[testNode.id]
		local output2 = calcFunc({
			removeNodes = { [testNode] = true },
			addNodes = { [origNode] = true }
		})
		assert.is_truthy(output2, "calcFunc with removeNodes+addNodes should return output")
	end)

	it("timeless jewel comparison: removeNodes/addNodes on conquered nodes changes output", function()
		-- This test simulates the timeless jewel conquest state without loading LUT data,
		-- since the LUT binary files don't load in the headless test environment.
		local spec = build.spec

		-- Allocate path to nearest jewel socket
		local socketNode = allocatePathToSocket(spec)
		spec:BuildAllDependsAndPaths()
		runCallback("OnFrame")
		assert.is_truthy(socketNode, "Should find a jewel socket")

		-- Find allocated nodes in the socket's large radius
		local nodesInRadius = findAllocatedNodesInRadius(spec, spec.nodes[socketNode.id], 3)
		assert.is_true(#nodesInRadius > 0, "Should have allocated nodes in radius")

		-- Simulate conquest: mark node as conquered and modify its modList
		-- (In a real build, BuildAllDependsAndPaths does this using LUT data)
		-- We do this AFTER runCallback to avoid the modList being reset by BADP
		local conqueredNode = nodesInRadius[1]
		local origNode = spec.tree.nodes[conqueredNode.id]
		conqueredNode.conqueredBy = { id = 10000, conqueror = { id = 1, type = "karui" } }
		-- Replace the conquered node's modList entirely with a known +100 Life mod
		conqueredNode.modList = new("ModList")
		conqueredNode.modList:NewMod("Life", "BASE", 100, "Timeless Jewel")

		-- Get calculator (this snapshots the current state including our fake conquest)
		local calcFunc, calcBase = build.calcsTab:GetMiscCalculator(build)
		local lifeWithConquest = calcBase.Life

		-- Build override like ItemsTab does: revert conquered node to original
		local output = calcFunc({
			removeNodes = { [conqueredNode] = true },
			addNodes = { [origNode] = true }
		})
		local lifeReverted = output.Life

		-- The outputs should differ: conquered node gives +100 Life, original does not
		assert.are_not.equals(lifeWithConquest, lifeReverted,
			"Reverting conquered node should change Life output")
	end)

	it("Thread of Hope enables allocation of unconnected nodes", function()
		local spec = build.spec

		-- Allocate path to nearest jewel socket
		local socketNode = allocatePathToSocket(spec)
		spec:BuildAllDependsAndPaths()
		runCallback("OnFrame")
		assert.is_truthy(socketNode, "Should find a jewel socket")

		-- Equip Thread of Hope
		local item = equipThreadOfHope(socketNode)
		spec:BuildAllDependsAndPaths()
		runCallback("OnFrame")

		-- Find a node in radius that has intuitiveLeapLikesAffecting
		local targetNode
		local inRadius = spec.nodes[socketNode.id].nodesInRadius
			and spec.nodes[socketNode.id].nodesInRadius[item.jewelRadiusIndex]
		for nodeId in pairs(inRadius or { }) do
			local node = spec.nodes[nodeId]
			if node and not node.alloc and #node.intuitiveLeapLikesAffecting > 0
			and node.type ~= "Mastery" and node.type ~= "Keystone" then
				targetNode = node
				break
			end
		end

		assert.is_truthy(targetNode, "Should find an unallocated node affected by Thread of Hope")

		-- Allocate the node through Thread of Hope
		spec:AllocNode(targetNode)
		spec:BuildAllDependsAndPaths()
		runCallback("OnFrame")

		-- Verify the node is allocated but not connected to start
		assert.is_true(targetNode.alloc, "Node should be allocated")
		assert.is_false(targetNode.connectedToStart, "Node should not be connected to start")

		-- NodesInIntuitiveLeapLikeRadius should return this node
		local nodesInLeapRadius = spec:NodesInIntuitiveLeapLikeRadius(spec.nodes[socketNode.id])
		local found = false
		for _, node in ipairs(nodesInLeapRadius) do
			if node.id == targetNode.id then
				found = true
				break
			end
		end
		assert.is_true(found, "NodesInIntuitiveLeapLikeRadius should include the allocated node")
	end)

	it("Thread of Hope removal comparison removes dependent nodes via override", function()
		local spec = build.spec

		-- Allocate path to nearest jewel socket
		local socketNode = allocatePathToSocket(spec)
		spec:BuildAllDependsAndPaths()
		runCallback("OnFrame")
		assert.is_truthy(socketNode, "Should find a jewel socket")

		-- Equip Thread of Hope
		local item = equipThreadOfHope(socketNode)
		spec:BuildAllDependsAndPaths()
		runCallback("OnFrame")

		-- Find and allocate a node through Thread of Hope
		local targetNode
		local inRadius = spec.nodes[socketNode.id].nodesInRadius
			and spec.nodes[socketNode.id].nodesInRadius[item.jewelRadiusIndex]
		for nodeId in pairs(inRadius or { }) do
			local node = spec.nodes[nodeId]
			if node and not node.alloc and #node.intuitiveLeapLikesAffecting > 0
			and node.type ~= "Mastery" and node.type ~= "Keystone" then
				targetNode = node
				break
			end
		end

		assert.is_truthy(targetNode, "Should find a node to allocate through Thread of Hope")

		spec:AllocNode(targetNode)
		spec:BuildAllDependsAndPaths()
		runCallback("OnFrame")

		-- Build override like ItemsTab does: remove nodes only reachable through the jewel
		local override = { removeNodes = { } }
		local nodesToRemove = spec:NodesInIntuitiveLeapLikeRadius(spec.nodes[socketNode.id])
		for _, node in ipairs(nodesToRemove) do
			if not node.connectedToStart then
				override.removeNodes[node] = true
			end
		end

		-- The target node should be in removeNodes
		assert.is_truthy(override.removeNodes[spec.nodes[targetNode.id]],
			"Node allocated through Thread of Hope should be in removeNodes")

		-- calcFunc with the override should produce valid output
		local calcFunc, _ = build.calcsTab:GetMiscCalculator(build)
		local output = calcFunc(override)
		assert.is_truthy(output, "calcFunc with removeNodes should return output")
	end)
end)
