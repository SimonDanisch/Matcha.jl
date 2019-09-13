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
# If a pattern doesn't need to match
isoptional(x) = 0 in greediness(x)

abstract type MatchFunc end

struct Matcher{F, NArgs}
    f::F
    function Matcher{F, NArgs}(f) where {F, NArgs}
        if NArgs > 2
            error("""
            Matcher function must have either one argument
            `f(value), or two: f(value, match_history).
            Found $(NArgs) arguments for $(f).
            """)
        end
        return new{F, NArgs}(f)
    end
end

@Base.pure function static_n_args(f)
    ms = methods(f)
    isempty(ms) && return 0
    return maximum((m.nargs for m in ms)) - 1
end

function Matcher(f::T) where T
    return Matcher{T, static_n_args(f)}(f)
end
function Matcher(greed::Greed)
    return Greed(Matcher(greed.x), greed.range)
end

trymatch(ms::MatchSteering, val, history) = trymatch(ms.x, val, history)
function trymatch(f::Matcher{T, N}, val, history) where {T, N}
    if N === 2 # matcher function requiring history
        f.f(val, history)
    elseif N === 1 # normal matcher function
        f.f(val)
    elseif N === 0 # value comparison
        f.f == val
    else
        # constructor of Matcher assert N < 3, so we should never get here
        false
    end
end

struct History{T, VT, ST}
    buffer::T # optional record of elements for iterators that are volatile. If not volatile, this will be the actual iterator
    matches::Vector{VT} # flattened list of views for each sub pattern match
    last_begin::Ref{ST} # state of last pattern match begin
    env::Dict{Symbol, Any} # environment for more complex saving of matched variables
end
@inline Base.getindex(h::History, i::Integer) = h.matches[i]
@inline Base.getindex(h::History, key::Symbol) = h.env[key]
@inline Base.haskey(h::History, key::Symbol) = haskey(h.env, key)

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
        Ref(state),
        Dict{Symbol, Any}()
    )
end

"""
Function that walks through `list` and saves `elem` in some way
"""
function next(history::History, list, state)
    elem_state = iterate(list, state)
    elem_state === nothing && return nothing
    elem, state = elem_state
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
    History(_copy(h.buffer), _copy(h.matches), _copy(h.last_begin), deepcopy(h.env))
end
function view_constructor(list::AbstractArray, a, b)
    view(list, a:b)
end
function view_constructor(list::AbstractString, a, b)
    safe_substring(list, a, b)
end

function finish_match(history, idx, matched, last_begin, state)
    matched = matched && last_begin <= state
    if matched
        history[idx] = last_begin:state
    end
    matched, history, state
end


function inner_matchat(
        list, last_state,
        patterns::NTuple{N, Any},
        history = [0:0 for i in 1:N]
    ) where N
    _inner_matchat(list, last_state, map(Matcher, patterns), 1, history)
end

function _inner_matchat(
        list, last_state,
        patterns::NTuple{N, Any}, pattern_idx,
        history
    ) where N
    elem_state = iterate(list, last_state)
    elem_state === nothing && return (false, history, last_state, 0)
    elem, state = elem_state
    matches = 0; lastmatchstate = last_state
    last_begin = last_state
    pattern = patterns[1]
    last_pattern = N === 1; patterns_left = N > 1
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
            if !enough || last_pattern
                return finish_match(history, pattern_idx, enough, last_begin, enough ? lastmatchstate : state)..., matches # we fail or not, depending whether we have enough
            end
            if patterns_left # if more than one pattern is left to match
                # okay, we failed but already have enough.
                # The only chance to continue is that next pattern matches
                if matches > 0 # If we already matched anything so far
                    finish_match(history, pattern_idx, true, last_begin, lastmatchstate)
                end
                return _inner_matchat(list, last_state, tail(patterns), pattern_idx + 1, history)
            end
        end
        # after match, needs to update enough
        enough = matches in greedrange
        last_allowed_match = matches == last(greedrange)
        # We're at the last allowed match for pattern, and there are no patterns left
        # This is it, we did it :)
        if last_pattern && last_allowed_match # rest is empty and we have enough -> stop!
            res = finish_match(history, pattern_idx, true, last_begin, lastmatchstate)
            return res..., matches
        end
        if patterns_left && enough
            # we're in a state were the current pattern can/should stop matching
            # this is where a match of the next pattern could end things!
            if last_allowed_match # we actually are at the last allowed
                finish_match(history, pattern_idx, true, last_begin, lastmatchstate)
                return _inner_matchat(list, state, tail(patterns), pattern_idx + 1, history)
            else
                # We can't know if the next pattern will end this match - since it should only do this
                # If the whole remaining pattern matches. So only thing we can do is, to
                # start matching the remaining pattern from here
                finish_match(history, pattern_idx, true, last_begin, lastmatchstate - 1)
                ismatch, history2, state2, n = _inner_matchat(list, last_state, tail(patterns), pattern_idx + 1, history)
                # n could be 0 if all remaining patterns are optional. In that case we
                # We don't actually want to terminate the current pattern
                (ismatch && n > 0) && return true, history2, state2, matches
            end
        end

        # we matched!
        # But if we have enough and the next pattern starts matching, we must stop here
        last_state = state
        elem_state = iterate(list, state)
        if elem_state === nothing
            # this madness is over!
            # if succesfull or not depends on whether we have enough and no rest!
            rest_is_optional = all(isoptional, tail(patterns))
            success = enough && (last_pattern || rest_is_optional)
            return finish_match(history, pattern_idx, success, last_begin, success ? lastmatchstate : state)..., matches
        end
        # okay, we're here, meaning we matched in some way and can continue making history!
        elem, state = elem_state
    end
    return false, history, last_state, matches # should be dead code
end

function matchat(
        list, patterns::Tuple,
    )
    matchat(list, 1, patterns)
end
function matchat(
        list, state, patterns::Tuple,
    )
    matched, hist, state, n = inner_matchat(
        list, state, patterns
    )
    matched, hist
end

function matchone(
        list, patterns::Tuple,
    )
    matchone(list, 1, patterns)
end
function matchone(
        list, state, patterns::Tuple,
    )
    _matchone(list, state, map(Matcher, patterns))
end
function _matchone(
        list, state, patterns::Tuple,
    )
    history = [0:0 for i in 1:length(patterns)]
    while true
        match, history, _, n = _inner_matchat(list, state, patterns, 1, history)
        match && return true, history
        elem_state = iterate(list, state)
        elem_state === nothing && break
        elem, state = elem_state
    end
    return false, history
end

function matchitall(
        list, patterns::Tuple,
    )
    matchitall(list, 1, patterns)
end

# TODO find better non clashing name with Base
function matchitall(
        list, state, patterns::Tuple,
    )
    history = History(list, state)
    matches = typeof(history)[]
    while true
        history = History(list, state)
        match, history, _, n = inner_matchat(list, state, patterns, history)
        if match
            push!(matches, history)
        end
        elem_state = iterate(list, state)
        elem_state === nothing && break
        elem, state = elem_state
    end
    return matches
end

function forward(x, elem, state, n)
    for i in 1:n
        elem_state = iterate(x, state)
        elem_state === nothing && break
        elem, state = elem_state
    end
    elem, state
end
slength(x::Union{Tuple, AbstractArray}) = length(x)
slength(x) = 1

@inline firstindex(v::History) = firstindex(v.matches)
@inline lastindex(v::History) = lastindex(v.matches)

@inline firstindex(v::SubArray) = parentindices(v)[1][1]
@inline firstindex(v::Union{Vector, Tuple}) = firstindex(first(v))

@inline lastindex(v::SubArray) = parentindices(v)[1][end]
@inline lastindex(v::Union{Vector, Tuple}) = lastindex(last(v))

function matchreplace(f, list, patterns)
    matches = matchitall(list, patterns)
    isempty(matches) && return copy(list)
    result = similar(list, 0)
    elem_state = iterate(list)
    i = 1
    cmatch = matches[i]
    while elem_state !== nothing
        elem, state = elem_state
        last_state = state
        isreplace = i <= length(matches) && last_state == firstindex(cmatch)
        replacements, n = if isreplace
            i += 1
            n = sum(map(slength, cmatch.matches))
            elem, state = forward(list, elem_state, n - 1)
            tmp = f(cmatch)
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
        elem_state = iterate(list, state)
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
        N =  sum(map(slength, cmatch.matches))
        @assert (b - a) == (N - 1) "$a $b $N"
        a < lastidx && continue # ignore matches that go back
        append!(result, view(list, lastidx:a-1))
        lastidx = b + 1
        tmp = f(cmatch)
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
