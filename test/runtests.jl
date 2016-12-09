using Matcha
using Base.Test

# strings
x = "hey 1yo whatup?"

matched, matches = matchat(x, (
    Greed(x-> x in ('h', 'y', 'e'), 3:3),
    ' ',
    isnumber
))

x = "(ɔ◔‿◔)ɔ ♥ (⊙.⊙(☉̃ₒ☉)⊙.⊙)"

matched, matches = matchat(x, (
    '(', anything,),')'
))

import Matcha: History, inner_match_at
inner_match_at(x, 2, anything, (), History(x, 2))
inner_match_at(x, 2,anything,(),History(x, 2))
# at beginning
x = [1,2,3,4,5,6]
test1(x) = x == 2
test2(x) = x == 3
matched, matches = matchat(x, (isodd, test1, test2))
@test matched
@test matches == [view(x, 1:3)]

# at end
x = [1,2,3,1,2,3]
match, matches = matchat(x, 4, (isodd, test1, test2))
@test match
@test matches == [view(x, 4:6)]

# at middle
x = [1,2,1,2,3,3]
match, matches = matchat(x, 3, isodd, (test1, test2), Int[])
@test match
@test matches == [1,2,3]

# at end
match, matches = matchat(x, 6, isodd, (test1, test2), Int[])
@test !match
@test matches == [3]
# even more endy
match, matches = matchat(x, 7, isodd, (test1, test2), Int[])
@test !match
@test matches == Int[]

# with values
matchat(x, 3, 1, (2, 3), Int[])
@test !match
@test matches == Int[]

# test greed + match all
x = [1,2,3,4,5,6,7]
match, matches = matchat(x, 1, 1, (Greed(x-> true), 5), Int[])
@test match
@test matches == Int[(1:5)...]

match, matches = matchat(x, 4, 4, (Greed(x-> true), 7), Int[])
@test match
@test matches == Int[(4:7)...]


x = [1,2,3,4,5,6,7]
match, matches = matchat(x, 1, Greed(1, 0:1), (), Int[])
@test match
@test matches == Int[1]
