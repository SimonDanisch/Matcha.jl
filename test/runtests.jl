using Matcha
using Base.Test

# strings
x = "hey 1yo whatup?"

matched, matches = matchat(x, (
    Greed(x-> x in ('h', 'y', 'e'), 3:3),
    ' ',
    isnumber
))


matched, matches = matchat(x, (
    Greed(x-> x in ('h', 'y', 'e'), 3:3),
    ' ',
    isnumber
))
@test matches == [SubString(x, 1, 3), SubString(x, 4, 4), SubString(x, 5, 5)]

x = "(ɔ◔‿◔)ɔ ♥ (⊙.⊙(☉̃ₒ☉)⊙.⊙)"

matched, matches = matchat(x, (
    '(', anything, ')'
))
@test matches[1] == "("
@test matches[2] == "ɔ◔‿◔"
@test matches[3] == ")"

# at beginning
x = [1,2,3,4,5,6]
test1(x) = x == 2
test2(x) = x == 3
matched, matches = matchat(x, (isodd, test1, test2))
@test matches == [view(x, 1:1), view(x, 2:2), view(x, 3:3)]

# at end
x = [1,2,3,1,2,3]
match, matches = matchat(x, 4, (isodd, test1, test2))
@test vcat(matches...) == [1,2,3]

# at middle
x = [1,2,1,2,3,3]
match, matches = matchat(x, 3, (isodd, test1, test2))
@test vcat(matches...) == [1,2,3]

# at end
match, matches = matchat(x, 6, (isodd, test1, test2))
@test !match
@test vcat(matches...) == [3] # we don't delete elements in match history

# even more endy
match, matches = matchat(x, 7, (isodd, test1, test2))
@test !match
@test vcat(matches...) == Int[]

# with values
match, matches = matchat(x, 3, (1, 2, 3))
@test vcat(matches...) == [1,2,3]

# test greed + match all
x = [1,2,3,4,5,6,7]
match, matches = matchat(x, 1, (1, anything, 5))
@test vcat(matches...) == Int[(1:5)...]

match, matches = matchat(x, 4, (4, anything, 7))
@test vcat(matches...) == Int[(4:7)...]


x = [1,2,3,4,5,6,7]
match, matches = matchat(x, 1, (Greed(1, 0:1), ))
@test vcat(matches...) == Int[1]
