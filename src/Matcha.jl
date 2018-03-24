__precompile__(true)
module Matcha

import Base: tail, @pure

abstract type MatchSteering end
struct Greed{F, T} <: MatchSteering
    x::F
    range::T
end

Greed(x::F, limit::T) where {F, T<:Integer} = Greed{F, Range{T}}(x, 1:limit)
Greed(x::F) where {F} = Greed(x, 1:typemax(Int))

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

struct History{T, VT, ST}
    buffer::T # optional record of elements for iterators that are volatile. If not volatile, this will be the actual iterator
    matches::Vector{VT} # flattened list of views for each sub pattern match
    last_begin::Ref{ST} # state of last pattern match begin
end
@inline Base.getindex(h::History, i::Integer) = h.matches[i]

# trait system
Base.@pure needs_recording(x) = false
Base.@pure view_type(x) = SubArray[]
Base.@pure view_type(x::T) where {T <: AbstractString} = SubString{T}[]
Base.@pure function buffer_type(x)
    needs_recording(x) ? eltype(x)[] : x
end

function History(list, state)
    History(
        buffer_type(list),
        view_type(list),
        Ref(state)
    )
end

"""
Function that walks through `list` and saves `elem` in some way
"""
function Base.next(history::History, list, state)
    elem, state = next(list, state)
    if needs_recording(history)
        push!(history.buffer, elem)
    end
    elem, state
end

function safe_substring(s::AbstractString, a, b)
    while !isvalid(s, a) a += 1 end
    while !isvalid(s, b) b -= 1 end
    SubString(s, a, b)
end

# seems like copy itself is not generic enough to just use it on any type
_copy(x) = copy(x)
_copy(x::String) = x
_copy(x::Ref) = Ref(x[])

function Base.copy(h::History)
    History(_copy(h.buffer), _copy(h.matches), _copy(h.last_begin))
end
function view_constructor(h::History{X, T, Y}, a, b) where {X, Y, T <: SubArray}
    view(h.buffer, a:b)
end
function view_constructor(h::History{X, T, Y}, a, b) where {X, Y, T <: SubString}    
    safe_substring(h.buffer, a, b)
end
function finish_match(matched, h::History{T, VT, ST}, state) where {T, VT, ST}
    if matched
        push!(h.matches, view_constructor(h, h.last_begin[], state))
    end
    matched, h, state
end
function start_match(history, state)
    history.last_begin[] = state
end

function inner_matchat(
        list, last_state,
        patterns::NTuple{N, Any},
        history = History(list, last_state)
    ) where N
    done(list, last_state) && return false, history, last_state, 0
    matches = 0; lastmatchstate = last_state
    start_match(history, last_state)
    elem, state = next(history, list, last_state)
    pattern = patterns[1]
    while true
        # greed can make one fail, but it depends on the circumstances
        greedrange = greediness(pattern)
        enough = matches in greedrange # we have enough matches when in the range of greed

        # okay lets get matchin'
        matched = trymatch(pattern, elem, history)

        if matched
            matches += 1
            lastmatchstate = last_state
        else
            # we don't have enough matches yet to fail matching, or we don't have any more patterns to match
            if !enough || N == 1
                return finish_match(enough, history, enough ? lastmatchstate : state)..., matches # we fail or not, depending whether we have enough
            end
            if N > 1
                # okay, we failed but already have enough.
                # The only chance to continue is that next pattern matches
                # this is final, so no copy of history for backtracking needed
                if matches > 0
                    finish_match(true, history, lastmatchstate)
                end
                return inner_matchat(list, last_state, tail(patterns), history)
            end
        end
        # after match, needs to update enough
        enough = matches in greedrange

        if N > 1 && enough
            # we're in a state were the current pattern can/should stop matching
            # this is where a match of the next pattern could end things!
            if matches == last(greedrange) # we actually are at the last allowed
                finish_match(true, history, lastmatchstate)
                return inner_matchat(list, state, tail(patterns), history)
            else
                # a copy of history is needed, since we can backtrack
                newbranch = copy(history)
                finish_match(true, newbranch, lastmatchstate - 1)
                ismatch, history2, state2, n = inner_matchat(list, last_state, tail(patterns), newbranch)
                (ismatch && n > 0) && return true, history2, state2, matches
            end
        elseif N == 1 && matches == last(greedrange) # rest is empty and we have enough -> stop!
            res = finish_match(true, history, lastmatchstate)
            return res..., matches
        end

        # we matched!
        # But if we have enough and the next pattern starts matching, we must stop here
        if done(list, state)
            # this madness is over!
            # if succesfull or not depends on whether we have enough and no rest!
            success = enough && (N == 1 || all(x-> 0 in greediness(x), tail(patterns)))
            return finish_match(success, history, success ? lastmatchstate : state)..., matches
        end
        # okay, we're here, meaning we matched in some way and can continue making history!
        last_state = state;
        elem, state = next(history, list, last_state)
    end
    return false, history, last_state, matches # should be dead code
end

function matchat(
        list, patterns::Tuple,
    )
    matchat(list, start(list), patterns)
end
function matchat(
        list, state, patterns::Tuple,
    )
    history = History(list, state)
    matched, hist, state, n = inner_matchat(
        list, state, patterns, history
    )
    matched, hist.matches
end

function matchone(
        list, patterns::Tuple,
    )
    matchone(list, start(list), patterns)
end
function matchone(
        list, state, patterns::Tuple,
    )
    history = History(list, state)
    while !done(list, state)
        history = History(list, state)
        match, history, _, n = inner_matchat(list, state, patterns, history)
        match && return true, history.matches
        elem, state = next(list, state)
    end
    return false, history.matches
end

function matchitall(
        list, patterns::Tuple,
    )
    matchitall(list, start(list), patterns)
end

# TODO find better non clashing name with Base
function matchitall(
        list, state, patterns::Tuple,
    )
    history = History(list, state)
    matches = typeof(history.matches)[]
    while !done(list, state)
        history = History(list, state)
        match, history, _, n = inner_matchat(list, state, patterns, history)
        if match
            push!(matches, history.matches)
        end
        elem, state = next(list, state)
    end
    return matches
end

function forward(x, elem, state, n)
    for i=1:n
        done(x, state) && break
        elem, state = next(x, state)
    end
    elem, state
end
slength(x::Union{Tuple, AbstractArray}) = length(x)
slength(x) = 1

if VERSION < v"0.7.0-DEV.3020"
    parentindices(v::SubArray) = v.indexes
end

@inline firstindex(v::SubArray) = parentindices(v)[1][1]
@inline firstindex(v::Union{Vector, Tuple}) = firstindex(first(v))

@inline lastindex(v::SubArray) = parentindices(v)[1][end]
@inline lastindex(v::Union{Vector, Tuple}) = lastindex(last(v))

function matchreplace(f, list, patterns)
    matches = matchitall(list, patterns)
    isempty(matches) && return copy(list)
    result = similar(list, 0)
    state, i = start(list), 1
    cmatch = matches[i]
    while !done(list, state)
        last_state = state
        elem, state = next(list, state)
        isreplace = i <= length(matches) && last_state == firstindex(cmatch)
        replacements, n = if isreplace
            i += 1
            n = sum(map(slength, cmatch))
            elem, state = forward(list, elem, state, n - 1)
            tmp = f(cmatch...)
            r = isa(tmp, Tuple) ? tmp : (tmp,)
            if i <= length(matches)
                cmatch = matches[i]
            end
            r, n
        else
            (elem,), 1
        end
        for r in replacements
            push!(result, r)
        end
    end
    result
end

function matchreplace(f, list::AbstractVector, patterns)
    matches = matchitall(list, patterns)
    isempty(matches) && return copy(list)
    result = similar(list, 0)
    lastidx = 1
    for cmatch in matches
        a, b = firstindex(cmatch), lastindex(cmatch)
        N =  sum(map(slength, cmatch))
        @assert (b - a) == (N - 1) "$a $b $N"
        a < lastidx && continue # ignore matches that go back
        append!(result, view(list, lastidx:a-1))
        lastidx = b + 1
        tmp = f(cmatch...)
        r = isa(tmp, Tuple) ? tmp : (tmp,)
        push!(result, r...)
    end
    append!(result, @view list[lastidx:end])
    result
end

alwaysmatch(x) = true
const anything = Greed(alwaysmatch)

export matchat, matchone, matchitall, matchreplace
export Greed
export anything


end # module
