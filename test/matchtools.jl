
nevermatch(x) = false
alwaysmatch(x) = true

abstract MatchSteering
immutable Greed{T} <: MatchSteering
    x
    range::T
end
Base.:(*)(x, ::typeof(*)) = Greed(x, 0:typemax(Int))
Base.:(*)(x, ::typeof(+)) = Greed(x, 1:typemax(Int))

Greed(x, limit::Int) = Greed{Range{Int}}(x, 1:limit)
Greed(x) = Greed(x, 1:typemax(Int))

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

function clean(matches, patterns)
    map(matches) do match
        map(zip(match, patterns)) do mp
            match, pattern = mp
            # if greediness allows for exactly one match, we unpack the match
            greediness(pattern) == 1:1 ? match[1] : match
        end
    end
end

# abstract over different match history approaches
add_match(matches::AbstractVector, match) = push!(matches, match)
hasmatched(pattern, matches::AbstractVector) = hasmatched(pattern, length(matches))

add_match(matches::Int, match) = matches+1
hasmatched(pattern, matches::Int) = matches in greediness(pattern)

function atomic_match{F}(atom::F, x, state, elem, matches = eltype(x)[])
    matched_items
    while true
        if trymatch(p, elem, tmp_matches)
            matched_items += 1
            matches = add_match(matches, elem)
            (matched_items in greediness(atom)) || break # only continue as long as greed allows
            if startswith(x, elem, state, patterns[i:end]) # or if we find the matching end sequence
                break
            end
            elem, state = next(x, state)
        elseif !hasmatched(matches) && 0 in greediness(p) # pattern is optional, so its allowed not to match
            break
        else # all other non matches are not allowed!!
            return state, elem, matches
        end
    end
    return state, elem, matches
end

function _ismatch{N}(x, atoms::Vararg{Any, N}; matchall=false)
    _ismatch(x, atoms, matchall=matchall)
end

function _ismatch{N}(x, atoms::NTuple{N, Any}; matchall=false)
    _ismatch(x, atoms, start(x), matchall=matchall)
end

function starts_with(x, state, pattern::Tuple{})
    false
end

function match_at(x, state, elem, patterns, pstate=1)
    for p in patterns

    end
end
import Base: tail

"""
Test if number of matches of a atom is in the range of allowed values.
returns two bools:
first bool indicates if the search can go on, even if not in range.
second bool indicates if the greed test is passed.
"""
function testgreed(atom, matches::Int)
    range = greediness(atom)
    return matches < first(range), matches in range
end
function match_all{F, N}(
        list,
        atom::F, rest::NTuple{N},
        state, history = ()
    )


end
function match_one{F, N}(
        list,
        atom::F, rest::NTuple{N},
        state, history = ()
    )
    for elem in list
        ismatch, matches = match_at(
            list, state, elem,
            atom, rest,
        )
    end
end

#=
Only one atom gets special treatment
=#
function match_at{F}(
        list, state, elem,
        atom::F, rest::Tuple{},
        history = ()
    )
    matches = 0
    if trymatch(atom, elem, history) # we have a match, well done!
        matches += 1
        # only start creating history when we actually match, or continue adding to it
        # might change type of history, so we need a change history
        _history, elem, state = makehistory!(list, state, history)

        while true
            # greed can make one fail, but it depends on wether one is currently fine
            greedrange = greediness(atom)
            enough = matches in greedrange
            # this madness is over when done, have a last match, or not matched
            # if succesfull or not depends on whether we're in the acceptable range of greed
            if done(list, state) || matches == last(greedrange) || !trymatch(atom, elem, _history)
                return enough, _history
            end

            # okay, we're here, meaning we matched in some way and the show must go on!
            _history, elem, state = makehistory!(list, state, _history)
            matches += 1
        end
    end
    # we need to immediately match, so this is a complete failure.
    # I'm deeply sorry wasting the time to even call (this function)
    # There is one token of hope though, and we can still pass when this atom was optional
    return (matches in greedrange(atom)), history
end

function makehistory(list, state, history)
    elem, state = next(list, state)
    _hist = if isa(history, Tuple)
        Any[elem]
    else
        push!(history, elem)
    end
    _hist, elem, state
end

function match_at{F, N}(
        list, state,
        atom::F, rest::NTuple{N},
        history = ()
    )
    matches = 0
    if trymatch(atom, elem, history) # we have a match, well done!
        matches += 1
        # only start creating history when we actually match, or continue adding to it
        # might change type of history, so we need a change history
        _history, elem, state = makehistory(list, state, history)
        # get the next batch of atoms to match
        atom2, rest2 = rest[1], tail(rest)
        while true
            # greed can make one fail, but it depends on wether one is currently fine
            greedrange = greediness(atom)
            enough = matches in greedrange
            # this madness is over when done, have a last match, or not matched
            # if succesfull or not depends on whether we're in the acceptable range of greed
            if done(list, state) || matches == last(greedrange) || !trymatch(atom, elem, _history)
                return enough, _history
            end

            # if we have enough matches to satisfy our greed, we can consider moving on with things
            if enough && !isempty(rest)
                ismatch, _history = match_at(list, state, atom2, rest2, state, _history)
                ismatch && return true, _history
            end

            # okay, we're here, meaning we matched in some way and can continue making history!
            _history, elem, state = makehistory(list, state, _history)
            matches += 1
        end
    end
    # first elem doesn't match and 0 matches are not acceptable for this atom
    is_0_enough = 0 in greediness(atom)
    if isempty(rest) || !is_0_enough
        # Greed test not passed and not matched?!?!?! Ծ_Ծ
        # This is a complete failure!
        # I'm deeply sorry wasting the time to even call (this function)
        return is_0_enough, history
    end
    # lucky. This atom is allowed to fail. Try next!
    return match_at(list, state, rest[1], tail(rest), state, history)
end

function _ismatch{N}(x, atoms::NTuple{N}, state; matchall = false)
    matches = NTuple{N, Vector{Any}}[]
    current_atom = 1
    states, tmp_matches = [], ntuple(x->Any[], Val{N})
    matched_state = state
    while true
        elem, state = next(x, state)
        atom = atoms[current_atom]
        if !trymatch(atom, elem, tmp_matches) # begin from start if not matching
            if 0 in greediness(atom) # false alert, we are allowed to skip this atom
                current_atom += 1
                atom = atoms[current_atom]
            else # chain of matches has been broken, reset all
                current_atom, atom = 1, atoms[current_atom]
                tmp_matches = ntuple(x->Any[], Val{N})
            end
        end
        # we don't have any matches yet and search for a match
        while !trymatch(atom, elem, tmp_matches) # continue until done or found match
            done(x, state) && return clean(matches, atoms), states
            elem, state = next(x, state)
        end
        # found a match. record state
        matched_state = ifelse(current_atom == 1, state, matched_state)
        elems_matched = 0
        next_atom = if current_atom + 1 <= length(atoms)
            atoms[current_atom+1]
        else
            nevermatch
        end
        while trymatch(atom, elem, tmp_matches)
            elems_matched += 1
            push!(tmp_matches[current_atom], elem)
            done(x, state) && break
            elem, state = next(x, state)
            (elems_matched in greediness(atom)) || break # only continue as long as greed allows
            if _ismatch(next_atom, elem, tmp_matches) # or if we find the matching end sequence

            end
        end
        current_atom = ifelse(elems_matched > 0, current_atom+1, 1)
        if current_atom > length(atoms)
            push!(states, matched_state)
            push!(matches, tmp_matches)
            matchall || break
            tmp_matches = ntuple(x->Any[], Val{N})
            current_atom = 1
        end
    end
    clean(matches, atoms), states
end

function forward(x, elem, state, n)
    for i=1:n
        done(x, state) && break
        elem, state = next(x, state)
    end
    elem, state
end

_length(x::Union{Tuple, Array}) = length(x)
_length(x) = 1
function _replace(f, x, atoms; matchall=false)
    matches, states = _ismatch(x, atoms, matchall=matchall)
    if isempty(matches)
        return copy(x)
    end
    result = similar(x, 0)
    state, i = start(x), 1
    while !done(x, state)
        elem, state = next(x, state)
        isreplace = i <= length(states) && state == states[i]
        replacements, n = if isreplace
            i += 1
            n = sum(map(_length, matches[i-1]))
            elem, state = forward(x, elem, state, n-1)
            tmp = f(matches[i-1]...)
            r = isa(tmp, Tuple) ? tmp : (tmp,)
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

isunless(x::Expr) = x.head == :gotoifnot
isunless(x) = false
islabelnode(x::LabelNode) = true
islabelnode(x) = false
isgoto(x::GotoNode) = true
isgoto(x) = false

function is_unless_label(label, hist, histpos)
    islabelnode(label) || return false
    unless = hist[histpos][1]
    unless_label = unless.args[2]
    unless_label == label.label
end
function is_goto_label(label, hist, histpos)
    islabelnode(label) || return false
    goto = hist[histpos][1]
    goto.label == label.label
end
function is_goto(goto, hist, histpos)
    isgoto(goto) || return false
    label = hist[histpos][1]
    goto.label == label.label
end
