util = require 'util'

DEFAULT_ALPHABET = 'abAcBdCDEefgFGHIhijkJKLlmMnNopqrOPQstuvwxyz'
DEFAULT_BLOCK_SIZE = 24
MIN_LENGTH = 5
MASK = (1 << DEFAULT_BLOCK_SIZE) - 1
MAPPING = [0...DEFAULT_BLOCK_SIZE].reverse()

setShareCodeConfig = (config) ->
  MIN_LENGTH = config.minLength
  DEFAULT_ALPHABET = config.alphabet
  DEFAULT_BLOCK_SIZE = config.blockSize
  MASK = (1 << DEFAULT_BLOCK_SIZE) - 1
  MAPPING = [0...DEFAULT_BLOCK_SIZE].reverse()

encodeShareCode = (n) ->
  nn = DEFAULT_ALPHABET.length
  enbase = (x) ->
    if x < nn
      DEFAULT_ALPHABET[x]
    else
      enbase(Math.floor(x / nn)) + DEFAULT_ALPHABET[x % nn]
  r = 0
  a = n & MASK
  for b, i in MAPPING
    r |= (1 << b) if a & (1 << i)
  code = enbase((n & ~MASK) | r)
  if code.length >= MIN_LENGTH
    code
  else
    DEFAULT_ALPHABET[0].repeat(MIN_LENGTH - code.length) + code

decodeShareCode = (code) ->
  nn = DEFAULT_ALPHABET.length
  r = 0
  for c, i in code.split('').reverse()
    r += DEFAULT_ALPHABET.indexOf(c) * (nn ** i)
  a = r & MASK
  n = 0
  for b, i in MAPPING
    n |= (1 << i) if a & (1 << b)
  (r & ~MASK) | n

genPassword = () ->
  ((Math.random() * 16 | 0).toString(16)  for _ in [1..4]).join('')

exports.genPassword = genPassword
exports.setShareCodeConfig = setShareCodeConfig
exports.encodeShareCode = encodeShareCode
exports.decodeShareCode = decodeShareCode
