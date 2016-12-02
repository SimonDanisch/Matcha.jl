module Matcha

import Base: tail

abstract MatchSteering
immutable Greed{F, T} <: MatchSteering
    x::F
    range::T
end

Greed{F, T<:Integer}(x::F, limit::T) = Greed{F, Range{T}}(x, 1:limit)
Greed{F}(x::F) = Greed(x, 1:typemax(Int))

greediness(x) = 1:1
greediness(x::Greed) = x.range


trymatch(ms::MatchSteering, val, history) = trymatch(ms.x, val, history)
function trymatch(f::Function, val, history)
    # an atomic pattern can use the match history by having two arguments
    if applicable(f, val, history)
        f(val, history)
    else
        f(val)
    end
end
# a pattern can also be a value
trymatch(val1, val2, history) = val1 == val2


"""
Function that walks through `list` and saves `elem` in some way
"""
function makehistory(list, elem, state, history)
    push!(history, elem)
    elem, state = next(list, state)
    history, elem, state
end

function match_at{F, N}(
        list, last_state,
        atom::F, rest::NTuple{N},
        history = []
    )
    done(list, last_state) && return false, history
    matches = 0
    elem, state = next(list, last_state)
    while true
        # greed can make one fail, but it depends on the circumstances
        greedrange = greediness(atom)
        enough = matches in greedrange # we have enough matches when in the range of greed

        # okay lets get matchin'
        matched = trymatch(atom, elem, history)

        if matched
            matches += 1
        else
            # we don't have enough matches yet to fail matching, or we don't have any more atoms to match
            if !enough || isempty(rest)
                return enough, history # we fail or not, depending whether we have enough
            end
            # okay, we failed but already have enough.
            # The only chance to continue is that next atom matches
            # this is final, so no copy of history for backtracking needed
            return match_at(list, last_state, rest[1], tail(rest), history)
        end
        # after match, needs to update enough
        enough = matches in greedrange


        if !isempty(rest) && enough
            # we're in a state were the current atom can/should stop matching
            # this is where a match of the next atom could end things!
            if trymatch(rest[1], elem, history) # lets save us the function call, when next doesn't match
                # a copy of history is needed, since we can backtrack
                ismatch, history2 = match_at(list, last_state, rest[1], tail(rest), copy(history))
                ismatch && return true, history2
            end
        elseif enough
            push!(history, elem)
            return true, history
        end

        # we matched!
        # But if we have enough and the next atom starts matching, we must stop here
        if done(list, state)
            push!(history, elem)
            # this madness is over!
            # if succesfull or not depends on whether we have enough and no rest!
            return enough && isempty(rest), history
        end
        # okay, we're here, meaning we matched in some way and can continue making history!
        push!(history, elem) # we count this one as a match!
        last_state = state;
        elem, state = next(list, state)
    end
    return false, history # should be dead code
end
match_result{T}(x::Vector{T}) = T[]
function match_at(
        list, atoms::Tuple,
    )
    match_at(list, start(list), atoms[1], tail(atoms), match_result(list))
end

export match_at
export Greed

end # module
