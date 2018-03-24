# Test for history and matchreplace
isunless(x::Expr) = x.head == :gotoifnot
isunless(x) = false
islabelnode(x::LabelNode) = true
islabelnode(x) = false
isgoto(x::GotoNode) = true
isgoto(x) = false

function is_unless_label(label, hist, histpos = 1)
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

ast = [
    NewvarNode(SlotNumber(6)),
    Expr(:(gotoifnot), Expr(:(call), :(==), SlotNumber(2), 10, ), 41, ),
    Expr(:(gotoifnot), Expr(:(call), :(==), SlotNumber(3), 22, ), 9, ),
    Expr(:(=), SlotNumber(7), 7, ),
    GotoNode(12),
    LabelNode(9),
    Expr(:(=), SlotNumber(7), 8, ),
    LabelNode(12),
    Expr(:(=), SlotNumber(6), SlotNumber(7), ),
    Expr(:(=), SSAValue(0), Expr(:(call), :(colon), 1, 100, ), ),
    Expr(:(=), SlotNumber(5), Expr(:(call), :(start), SSAValue(0), ), ),
    LabelNode(17),
    Expr(:(gotoifnot), Expr(:(call), :(!), Expr(:(call), :(done), SSAValue(0), SlotNumber(5), ), ), 38, ),
    Expr(:(=), SSAValue(1), Expr(:(call), :(next), SSAValue(0), SlotNumber(5), ), ),
    Expr(:(=), SlotNumber(4), Expr(:(call), :(getfield), SSAValue(1), 1, ), ),
    Expr(:(=), SlotNumber(5), Expr(:(call), :(getfield), SSAValue(1), 2, ), ),
    Expr(:(=), SlotNumber(6), Expr(:(call), :(+), SlotNumber(6), SlotNumber(4), ), ),
    Expr(:(=), SlotNumber(6), Expr(:(call), :(-), SlotNumber(6), 77, ), ),
    Expr(:(gotoifnot), Expr(:(call), :(==), SlotNumber(4), 77, ), 31, ),
    GotoNode(36),
    GotoNode(36),
    LabelNode(31),
    Expr(:(gotoifnot), Expr(:(call), :(==), SlotNumber(4), 99, ), 36, ),
    GotoNode(38),
    LabelNode(36),
    GotoNode(17),
    LabelNode(38),
    Expr(:return, SlotNumber(6), ),
    LabelNode(41),
    Expr(:return, 77, ),
]



ifelse_pattern = (
    isunless, # if branch
    anything, # if body
    isgoto, # goto to jump over else
    (l, h)-> is_unless_label(l, h, 1),
    anything,   # else body
    (l, h)-> is_goto_label(l, h, 3) # label matching above goto
)
while_pattern = (
    islabelnode, # loop goto label
    isunless, # while condition branch
    anything, # body
    Greed(islabelnode, 0:1), # optional continue label
    (l,h)-> is_goto(l, h, 1), # goto label, matching first label
    (l,h)-> is_unless_label(l, h, 2) # goto and break
)

if_pattern = (isunless, anything, is_unless_label)

matches = matchitall(ast, while_pattern)
@test length(matches) == 1
@test vcat(matches[1]...) == ast[12:27]

matches = matchitall(ast, ifelse_pattern)
@test length(matches) == 3
@test vcat(matches[1]...) == ast[3:8]
@test vcat(matches[2]...) == ast[19:25]
@test vcat(matches[3]...) == ast[23:27]


ast = matchreplace(ast, while_pattern) do loop_label, unless, whilebody, continue_label, goto, break_label
    condition = unless[1].args[1]
    whilebody = collect(whilebody)
    block = Expr(:block, whilebody...)
    Expr(:while, condition, block)
end

ast = matchreplace(ast, ifelse_pattern) do unless, ifbody, _1, _2, elsebody, _3
    condition = unless[1].args[1]
    ifbody = Expr(:block, ifbody...)
    elsebody = Expr(:block, elsebody...)
    Expr(:if, condition, ifbody, elsebody)
end

matches = matchitall(ast, if_pattern)
@test length(matches) == 1
@test vcat(matches[1]...) == ast[2:9]
