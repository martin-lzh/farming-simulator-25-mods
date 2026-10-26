-- Original routing logic. Engine access is supplied by the caller.
APMDistribution = {}
APMDistribution.KEEP = 0
APMDistribution.SELL = 1
-- Both distributing modes deliver first; they differ in what happens to the rest.
APMDistribution.DISTRIBUTE_STORE = 2
APMDistribution.DISTRIBUTE_SELL = 3

function APMDistribution.isMode(mode)
    return mode == 0 or mode == 1 or mode == 2 or mode == 3
end

function APMDistribution.isFinite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- Targets expose free(), add(liters) and remove(liters), returning observed deltas.
-- A source exposes available(), take(liters), release(liters), hold(liters) and
-- put(liters). Taken liters stay in the source's own buffer until released.
-- charge(target, liters) returns how many delivered liters were actually paid for.
-- No error is caught here: the game changes a storage or balance before it
-- notifies listeners, so each delivery is booked before the call that makes it.
function APMDistribution.distribute(source, targets, charge)
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
                source.release(taken)
                local accepted = target.add(taken)
                if not APMDistribution.isFinite(accepted) then accepted = 0 end
                accepted = math.max(0, math.min(taken, accepted))
                source.hold(taken - accepted)
                source.put(taken - accepted)
                if accepted > 0 then
                    local funded = charge(target, accepted)
                    if not APMDistribution.isFinite(funded) then funded = 0 end
                    local unpaid = accepted - math.max(0, math.min(accepted, funded))
                    if unpaid > 0 then
                        -- Roll back only stock actually removed from the destination.
                        source.hold(unpaid)
                        local removed = target.remove(unpaid)
                        if not APMDistribution.isFinite(removed) then removed = 0 end
                        removed = math.max(0, math.min(unpaid, removed))
                        source.release(unpaid - removed)
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

-- credit(revenue, onPaid) calls onPaid(observedRevenue) once, as soon as the
-- balance has changed and before balance listeners run.
function APMDistribution.sell(source, price, credit)
    if not APMDistribution.isFinite(price) or price <= 0 then
        return 0
    end
    local amount = source.take(source.available())
    if amount > 0 then
        local sold = 0
        credit(amount * price, function(paid)
            if not APMDistribution.isFinite(paid) then paid = 0 end
            sold = math.max(0, math.min(amount, paid / price))
            source.release(sold)
        end)
        source.put(amount - sold)
        return sold
    end
    return amount
end
