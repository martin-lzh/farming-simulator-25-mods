-- Original routing logic. Engine access is supplied by the caller.
APDDistribution = {}
APDDistribution.KEEP = 0
APDDistribution.SELL = 1
APDDistribution.DISTRIBUTE = 2

function APDDistribution.isMode(mode)
    return mode == 0 or mode == 1 or mode == 2
end

function APDDistribution.isFinite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- Targets expose free(), add(liters) and remove(liters), returning observed deltas.
-- A source exposes available(), take(liters) and put(liters).
-- charge(target, liters) returns how many delivered liters were actually paid for.
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
                local ok, accepted = pcall(target.add, taken)
                if not ok or not APDDistribution.isFinite(accepted) then accepted = 0 end
                accepted = math.max(0, math.min(taken, accepted))
                source.put(taken - accepted)
                if accepted > 0 then
                    local charged, funded = pcall(charge, target, accepted)
                    if not charged or not APDDistribution.isFinite(funded) then funded = 0 end
                    local unpaid = accepted - math.max(0, math.min(accepted, funded))
                    if unpaid > 0 then
                        -- Roll back only stock actually removed from the destination.
                        local removed = target.remove(unpaid)
                        source.put(removed)
                        accepted = accepted - removed
                    end
                end
                transferred = transferred + accepted
            end
        end
    end
    return transferred
end

-- credit(revenue) returns the observed money delta, not an assumed success flag.
function APDDistribution.sell(source, price, credit)
    if not APDDistribution.isFinite(price) or price <= 0 then
        return 0
    end
    local amount = source.take(source.available())
    if amount > 0 then
        -- The account adapter returns the observed balance delta, including when
        -- an engine notification throws after the balance has already changed.
        local ok, paid = pcall(credit, amount * price)
        if not ok or not APDDistribution.isFinite(paid) then paid = 0 end
        local sold = math.max(0, math.min(amount, paid / price))
        source.put(amount - sold)
        return sold
    end
    return amount
end
