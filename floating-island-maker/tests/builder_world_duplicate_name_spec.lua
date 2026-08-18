package.path = "scripts/?.lua;" .. package.path

package.preload["urhox-libs/3D"] = function() return {} end
package.preload["BlockCatalog"] = function() return {} end
package.preload["BlockMaterials"] = function() return {} end
package.preload["HouseTemplate"] = function() return {} end
package.preload["HtmlRoundedBoxGeometry"] = function() return {} end
package.preload["TransparentBlockGeometry"] = function() return {} end
package.preload["TriangularPrismGeometry"] = function() return {} end
package.preload["FacetedSolidGeometry"] = function() return {} end
package.preload["FullCylinderGeometry"] = function() return {} end
package.preload["BuilderTransformControls"] = function()
    return { Install = function() end }
end
package.preload["MakerTransformControls"] = function() return {} end
package.preload["ViewportCoordinates"] = function() return {} end
package.preload["CloudAtelierTheme"] = function() return {} end

local BuilderWorld = require("BuilderWorld")

assert(BuilderWorld._DuplicateBaseName("窗框 副本 副本 3") == "窗框",
    "legacy recursively appended copy suffixes must collapse to the authored base name")
assert(BuilderWorld._DuplicateBaseName("精灵副本") == "精灵副本",
    "an authored word ending in 副本 without a separator must remain intact")

local blocks = {
    { name = "窗框" },
    { name = "窗框 副本" },
    { name = "窗框 副本 2" },
    { name = "不相关组件 副本" },
}
assert(BuilderWorld._NextDuplicateName(blocks, "窗框 副本 2") == "窗框 副本 3",
    "copying a copy must advance a short sequence instead of appending another suffix")

local withGap = {
    { name = "门板 副本" },
    { name = "门板 副本 3" },
}
assert(BuilderWorld._NextDuplicateName(withGap, "门板 副本 3") == "门板 副本 2",
    "copy names should reuse the first available sequence without growing")

local many = {}
for index = 1, 500 do
    many[index] = { name = index == 1 and "栏杆 副本" or ("栏杆 副本 " .. tostring(index)) }
end
local nextName = BuilderWorld._NextDuplicateName(many, many[#many].name)
assert(nextName == "栏杆 副本 501" and #nextName < 32,
    "hundreds of continuous copies must keep a bounded stable name")

print("builder-world-duplicate-name-spec: ok")
