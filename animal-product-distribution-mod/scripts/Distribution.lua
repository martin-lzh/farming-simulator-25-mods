-- Original routing logic. Engine access is supplied by the caller.
APDDistribution = {}
APDDistribution.KEEP = 0
APDDistribution.SELL = 1
APDDistribution.DISTRIBUTE = 2

function APDDistribution.isMode(mode)
    return mode == 0 or mode == 1 or mode == 2
end

-- Targets expose free() and add(liters), returning the amount actually accepted.
-- A source exposes available(), take(liters) and put(liters).
function APDDistribution.distribute(source, targets, charge)
    local available = math.max(source.available(), 0)
    local totalCapacity = 0
    local capacities = {}
    for i, target in ipairs(targets) do
        capacities[i] = math.max(target.free(), 0)
        totalCapacity = totalCapacity + capacities[i]
    end
    if available <= 0 or totalCapacity <= 0 then
        return 0
    end
    local budget = math.min(available, totalCapacity)
    local transferred = 0
    for i, target in ipairs(targets) do
        local requested = math.min(target.free(), budget * capacities[i] / totalCapacity)
        if requested > 0 then
            local taken = source.take(requested)
            if taken > 0 then
                local accepted = target.add(taken)
                source.put(taken - accepted)
                transferred = transferred + accepted
                if accepted > 0 then
                    charge(target, accepted)
                end
            end
        end
    end
    return transferred
end

function APDDistribution.sell(source, price, credit)
    if price <= 0 then
        return 0
    end
    local amount = source.take(source.available())
    if amount > 0 then
        credit(amount * price)
    end
    return amount
end
