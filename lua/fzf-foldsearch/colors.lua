local M = {}

local function hex_to_rgb(hex)
  hex = hex:gsub('^#', '')
  return {
    r = tonumber(hex:sub(1, 2), 16),
    g = tonumber(hex:sub(3, 4), 16),
    b = tonumber(hex:sub(5, 6), 16),
  }
end

local function rgb_to_hex(r, g, b)
  return string.format('#%02x%02x%02x',
    math.max(0, math.min(255, math.floor(r + 0.5))),
    math.max(0, math.min(255, math.floor(g + 0.5))),
    math.max(0, math.min(255, math.floor(b + 0.5)))
  )
end

local function lerp(a, b, t)
  return a + (b - a) * t
end

local function interpolate(c1, c2, qnt)
  local rgb1 = hex_to_rgb(c1)
  local rgb2 = hex_to_rgb(c2)
  local result = {}

  if qnt == 1 then
    -- midpoint
    table.insert(result, rgb_to_hex(
      lerp(rgb1.r, rgb2.r, 0.5),
      lerp(rgb1.g, rgb2.g, 0.5),
      lerp(rgb1.b, rgb2.b, 0.5)
    ))
  else
    for i = 0, qnt - 1 do
      local t = i / (qnt - 1)
      table.insert(result, rgb_to_hex(
        lerp(rgb1.r, rgb2.r, t),
        lerp(rgb1.g, rgb2.g, t),
        lerp(rgb1.b, rgb2.b, t)
      ))
    end
  end

  return result
end

-- generate_colors({ { '#rgb1', '#rgb2', qnt }, ... }) -> list of hex colors
function M.generate_colors(spec)
  local result = {}
  for _, pair in ipairs(spec) do
    local c1, c2, qnt = pair[1], pair[2], pair[3]
    for _, color in ipairs(interpolate(c1, c2, qnt)) do
      table.insert(result, color)
    end
  end
  return result
end

return M
