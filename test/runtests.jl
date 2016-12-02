using Matcha
using Base.Test

# at beginning
x = [1,2,3,4,5,6]
test1(x) = x == 2
test2(x) = x == 3
match, matches = match_at(x, start(x), isodd, (test1, test2), Int[])
@test match
@test matches == [1,2,3]

# at end
x = [1,2,3,1,2,3]
match, matches = match_at(x, 4, isodd, (test1, test2), Int[])
@test match
@test matches == [1,2,3]

# at middle
x = [1,2,1,2,3,3]
match, matches = match_at(x, 3, isodd, (test1, test2), Int[])
@test match
@test matches == [1,2,3]

# at end
match, matches = match_at(x, 6, isodd, (test1, test2), Int[])
@test !match
@test matches == [3]
# even more endy
match, matches = match_at(x, 7, isodd, (test1, test2), Int[])
@test !match
@test matches == Int[]

# with values
match_at(x, 3, 1, (2, 3), Int[])
@test !match
@test matches == Int[]

# test greed + match all
x = [1,2,3,4,5,6,7]
match, matches = match_at(x, 1, 1, (Greed(x-> true), 5), Int[])
@test match
@test matches == Int[(1:5)...]

match, matches = match_at(x, 4, 4, (Greed(x-> true), 7), Int[])
@test match
@test matches == Int[(4:7)...]


x = [1,2,3,4,5,6,7]
match, matches = match_at(x, 1, Greed(1, 0:1), (), Int[])
@test match
@test matches == Int[1]
