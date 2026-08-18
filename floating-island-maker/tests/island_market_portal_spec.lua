package.path = "scripts/?.lua;" .. package.path

local IslandMarket = require("IslandMarket")
local IslandPortalNetwork = require("IslandPortalNetwork")
local PortalTemplate = require("PortalTemplate")

local PORTAL_ASSET_ID = PortalTemplate.ASSET_ID
local FILLER_ASSET_ID = "builtin:compose:sunny-meadow-cottage"

local assetStore = {}

function assetStore:Get(assetId)
    if assetId ~= PORTAL_ASSET_ID and assetId ~= FILLER_ASSET_ID then return nil end
    return {
        source = "builtin",
        assetId = assetId,
        versionId = "1.0.0",
    }
end

local function Binding(linkId, targetIslandId, targetInstanceId, generatedPeer)
    return {
        schema = IslandPortalNetwork.SCHEMA,
        linkId = linkId,
        targetIslandId = targetIslandId,
        targetInstanceId = targetInstanceId,
        generatedPeer = generatedPeer == true,
    }
end

local function Instance(id, assetId, portal)
    return {
        id = id,
        assetId = assetId,
        versionId = "1.0.0",
        x = id / 10,
        y = 0,
        z = -id / 20,
        rotationY = 0,
        scale = 1,
        portal = portal,
    }
end

local function Project(islandId, published, instances)
    return {
        schema = "island-project/v2",
        version = 2,
        islandId = islandId,
        name = islandId,
        published = published == true,
        updatedAt = 100,
        instances = instances,
    }
end

local function FindEntry(entries, islandId)
    for _, entry in ipairs(entries or {}) do
        if entry.project and entry.project.islandId == islandId then return entry end
    end
end

local function FindPortal(project)
    for _, instance in ipairs(project and project.instances or {}) do
        if instance.assetId == PORTAL_ASSET_ID then return instance end
    end
end

-- Both endpoints are published. Their sparse private instance ids must be
-- rewritten to the compact ids in the public snapshot without breaking the
-- reciprocal link.
local reciprocalLinkId = "published-link"
local sourceProject = Project("island-a", true, {
    Instance(4, FILLER_ASSET_ID),
    Instance(41, PORTAL_ASSET_ID, Binding(reciprocalLinkId, "island-b", 93, false)),
})
local targetProject = Project("island-b", true, {
    Instance(7, FILLER_ASSET_ID),
    Instance(93, PORTAL_ASSET_ID, Binding(reciprocalLinkId, "island-a", 41, true)),
})
local publishedProfile = assert(IslandMarket.BuildProfile({
    updatedAt = 101,
    items = { sourceProject, targetProject },
}, assetStore))

assert(#publishedProfile.items == 2, "both published islands must enter the public profile")
local publishedSource = assert(FindEntry(publishedProfile.items, "island-a"))
local publishedTarget = assert(FindEntry(publishedProfile.items, "island-b"))
local publishedSourcePortal = assert(FindPortal(publishedSource.project))
local publishedTargetPortal = assert(FindPortal(publishedTarget.project))
assert(publishedSourcePortal.id == 2 and publishedTargetPortal.id == 2,
    "sparse private endpoint ids must be compacted deterministically")
assert(publishedSourcePortal.portal
    and publishedSourcePortal.portal.targetIslandId == "island-b"
    and publishedSourcePortal.portal.targetInstanceId == 2,
    "the source endpoint must target the destination's remapped public id")
assert(publishedTargetPortal.portal
    and publishedTargetPortal.portal.targetIslandId == "island-a"
    and publishedTargetPortal.portal.targetInstanceId == 2,
    "the destination endpoint must target the source's remapped public id")

-- A portal model remains useful scenery when its bound destination is private,
-- but its live route must not leak into the published snapshot.
local unpublishedTargetProfile = assert(IslandMarket.BuildProfile({
    updatedAt = 102,
    items = {
        Project("public-source", true, {
            Instance(11, PORTAL_ASSET_ID, Binding("private-link", "private-target", 78, false)),
        }),
        Project("private-target", false, {
            Instance(78, PORTAL_ASSET_ID, Binding("private-link", "public-source", 11, true)),
        }),
    },
}, assetStore))
assert(#unpublishedTargetProfile.items == 1, "the private destination must not be published")
local decorativePortal = assert(FindPortal(unpublishedTargetProfile.items[1].project))
assert(decorativePortal.portal == nil,
    "a published source must lose its route when the target island is not published")

-- Remote input is untrusted. A one-way link and a link targeting an absent
-- island must both be stripped while the visible portal models survive.
local maliciousProfile = {
    schema = "island-market-profile/v1",
    ownerId = "spoofed-owner",
    items = {
        {
            publicationId = "one-way-a",
            name = "one-way-a",
            project = Project("raw-one-way-a", true, {
                Instance(31, PORTAL_ASSET_ID,
                    Binding("one-way-link", "raw-one-way-b", 62, false)),
            }),
        },
        {
            publicationId = "one-way-b",
            name = "one-way-b",
            project = Project("raw-one-way-b", true, {
                Instance(62, PORTAL_ASSET_ID),
            }),
        },
        {
            publicationId = "dangling",
            name = "dangling",
            project = Project("raw-dangling", true, {
                Instance(90, PORTAL_ASSET_ID,
                    Binding("missing-link", "missing-island", 999, false)),
            }),
        },
    },
    assets = {},
}
local sanitizedEntries = IslandMarket.NormalizeRemoteProfile(maliciousProfile, "owner-remote")
assert(#sanitizedEntries == 3, "sanitizing malformed routes must not remove their islands")
for _, entry in ipairs(sanitizedEntries) do
    local portal = assert(FindPortal(entry.project))
    assert(portal.portal == nil,
        "one-way and dangling remote portal metadata must be stripped defensively")
end

-- Visitor traversal only accepts the current cloud publication graph: same
-- owner, source still listed, target still listed, and a reciprocal pair.
local cloudEntries = IslandMarket.NormalizeRemoteProfile(publishedProfile, "owner-7")
local cloudSource = assert(FindEntry(cloudEntries, "island-a"))
local cloudTarget = assert(FindEntry(cloudEntries, "island-b"))
local cloudSourcePortal = assert(FindPortal(cloudSource.project))
local route = assert(IslandMarket.ResolvePublishedPortal(
    cloudEntries, cloudSource, cloudSourcePortal.id))
assert(route.sourceEntry == cloudSource and route.targetEntry == cloudTarget
    and route.ownerId == "owner-7" and route.targetInstance == FindPortal(cloudTarget.project),
    "a reciprocal pair between two current publications by one owner must resolve")

local nonCloudSource = IslandMarket.Copy(cloudSource)
nonCloudSource.source = "sample"
local nonCloudRoute, nonCloudError = IslandMarket.ResolvePublishedPortal(
    cloudEntries, nonCloudSource, cloudSourcePortal.id)
assert(not nonCloudRoute and nonCloudError == "source_not_published",
    "offline/sample islands must not enter published visitor traversal")

local differentOwnerEntries = IslandMarket.Copy(cloudEntries)
local differentOwnerSource = assert(FindEntry(differentOwnerEntries, "island-a"))
assert(FindEntry(differentOwnerEntries, "island-b")).ownerId = "owner-8"
local differentOwnerRoute, differentOwnerError = IslandMarket.ResolvePublishedPortal(
    differentOwnerEntries, differentOwnerSource, FindPortal(differentOwnerSource.project).id)
assert(not differentOwnerRoute and differentOwnerError == "target_not_published",
    "a portal must not cross into another author's publication graph")

local missingTargetEntries = { IslandMarket.Copy(cloudSource) }
local missingTargetRoute, missingTargetError = IslandMarket.ResolvePublishedPortal(
    missingTargetEntries, missingTargetEntries[1], FindPortal(missingTargetEntries[1].project).id)
assert(not missingTargetRoute and missingTargetError == "target_not_published",
    "a visitor cannot traverse to an island that is no longer published")

local brokenEntries = IslandMarket.Copy(cloudEntries)
local brokenSource = assert(FindEntry(brokenEntries, "island-a"))
local brokenTargetPortal = assert(FindPortal(assert(FindEntry(brokenEntries, "island-b")).project))
brokenTargetPortal.portal.linkId = "tampered-link"
local brokenRoute, brokenError = IslandMarket.ResolvePublishedPortal(
    brokenEntries, brokenSource, FindPortal(brokenSource.project).id)
assert(not brokenRoute and brokenError == "portal_pair_broken",
    "a non-reciprocal current publication must be rejected at traversal time")

-- A market refresh can replace the Explore entries while the visitor still
-- stands in the older rendered source scene. If that portal was rebound from
-- B to C, traversal must fail closed instead of combining old B metadata with
-- the new live graph and opening the wrong destination.
local reboundProfile = assert(IslandMarket.BuildProfile({ items = {
    Project("island-a", true, {
        Instance(4, FILLER_ASSET_ID),
        Instance(41, PORTAL_ASSET_ID, Binding("rebound-link", "island-c", 93, false)),
    }),
    Project("island-c", true, {
        Instance(7, FILLER_ASSET_ID),
        Instance(93, PORTAL_ASSET_ID, Binding("rebound-link", "island-a", 41, true)),
    }),
} }, assetStore))
local reboundEntries = IslandMarket.NormalizeRemoteProfile(reboundProfile, "owner-7")
local staleRoute, staleError = IslandMarket.ResolvePublishedPortal(
    reboundEntries, cloudSource, cloudSourcePortal.id)
assert(not staleRoute and staleError == "portal_pair_broken",
    "a stale rendered endpoint must not traverse through a newly rebound publication graph")

print("island-market-portal-spec: ok (publish remap, private stripping, remote sanitizing, visitor graph)")
