import Foundation

enum MathError: Error, Equatable {
    case empty, syntax, divisionByZero
    /// Too big for a result, or not a real number (the root of a negative one).
    case outOfRange
    case tooLong, tooComplex
}

/// What an expression came to.
struct MathResult: Equatable {
    var value: Decimal
    /// False for a bare number, "(5)", "-5" or "50%": nothing was calculated, so there is nothing to show.
    var usesOperator: Bool
}

/// Arithmetic on selected text, with a parser of its own instead of `NSExpression`, which would also run function
/// calls and key paths from text it was handed. Only numbers, `+ - × ÷ * / ^ %` and parentheses exist here, so
/// nothing else can run. Numbers are read as Vietnamese or English writes them (see `VietnameseNumber`) and added up
/// as decimals, so 0,1 + 0,2 is exactly 0,3.
///
///     expression := term (("+" | "-") term)*
///     term       := unary (("*" | "/" | "%") unary)*
///     unary      := ("+" | "-") unary | power
///     power      := postfix ("^" unary)?        right-associative, and binds tighter than a sign: -2^2 = -4
///     postfix    := primary "%"?                a percent when no operand follows: 50% is 0,5
///     primary    := number | "(" expression ")"
///
/// "%" between two operands is the remainder ("17 % 5"); after one it is a percent, which in a sum is a percent of
/// the left side ("100 + 10%" is 110) and a hundredth elsewhere ("200 * 15%" is 30).
enum MathExpression {
    static let maxLength = 200
    static let maxDepth = 64
    /// Whole exponents up to this size are worked out exactly; larger ones go through floating point.
    private static let exactExponent = 1000

    static func evaluate(_ text: String) -> Result<MathResult, MathError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.count <= maxLength else { return .failure(.tooLong) }
        do {
            var parser = Parser(tokens: try tokenize(trimmed))
            let operand = try parser.parseAll()
            return .success(MathResult(value: operand.plain, usesOperator: parser.operations > 0))
        } catch let error as MathError {
            return .failure(error)
        } catch {
            return .failure(.syntax)
        }
    }

    private enum Token: Equatable {
        case number(Decimal), plus, minus, times, divide, percent, power, open, close
    }

    private static func tokenize(_ text: String) throws -> [Token] {
        let characters = Array(text)
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
            } else if character.isASCIIDigit {
                guard let (value, end) = VietnameseNumber.scan(characters, from: index) else { throw MathError.syntax }
                tokens.append(.number(value))
                index = end
            } else {
                switch character {
                case "+": tokens.append(.plus)
                case "-", "−": tokens.append(.minus)
                case "*", "×": tokens.append(.times)
                case "/", "÷": tokens.append(.divide)
                case "%": tokens.append(.percent)
                case "^": tokens.append(.power)
                case "(": tokens.append(.open)
                case ")": tokens.append(.close)
                default: throw MathError.syntax
                }
                index += 1
            }
        }
        return tokens
    }

    /// A value, remembering whether it was written with a "%" that has not been applied yet.
    private struct Operand {
        var value: Decimal
        var isPercent = false

        /// A percent on its own is a hundredth.
        var plain: Decimal { isPercent ? value / 100 : value }
    }

    private struct Parser {
        let tokens: [Token]
        var position = 0
        var depth = 0
        var operations = 0

        init(tokens: [Token]) {
            self.tokens = tokens
        }

        var next: Token? { position < tokens.count ? tokens[position] : nil }

        mutating func parseAll() throws -> Operand {
            let operand = try parseExpression()
            guard position == tokens.count else { throw MathError.syntax }
            return operand
        }

        mutating func parseExpression() throws -> Operand {
            var left = try parseTerm()
            while let token = next, token == .plus || token == .minus {
                position += 1
                let right = try parseTerm()
                // "100 + 10%" adds a tenth of the 100.
                let amount = right.isPercent ? left.plain * right.value / 100 : right.plain
                left = Operand(value: try check(token == .plus ? left.plain + amount : left.plain - amount))
                operations += 1
            }
            return left
        }

        mutating func parseTerm() throws -> Operand {
            var left = try parseUnary()
            while let token = next {
                switch token {
                case .times:
                    position += 1
                    let right = try parseUnary()
                    left = Operand(value: try check(left.plain * right.plain))
                case .divide:
                    position += 1
                    let right = try parseUnary().plain
                    guard right != 0 else { throw MathError.divisionByZero }
                    left = Operand(value: try check(left.plain / right))
                case .percent where startsOperand(at: position + 1):
                    position += 1
                    let right = try parseUnary().plain
                    guard right != 0 else { throw MathError.divisionByZero }
                    left = Operand(value: try check(remainder(left.plain, right)))
                default:
                    return left
                }
                operations += 1
            }
            return left
        }

        mutating func parseUnary() throws -> Operand {
            depth += 1
            defer { depth -= 1 }
            guard depth <= MathExpression.maxDepth else { throw MathError.tooComplex }
            switch next {
            case .plus:
                position += 1
                return try parseUnary()
            case .minus:
                position += 1
                var operand = try parseUnary()
                operand.value = -operand.value
                return operand
            default:
                return try parsePower()
            }
        }

        mutating func parsePower() throws -> Operand {
            let base = try parsePostfix()
            guard next == .power else { return base }
            position += 1
            let exponent = try parseUnary()
            operations += 1
            return Operand(value: try power(base.plain, exponent.plain))
        }

        mutating func parsePostfix() throws -> Operand {
            var operand = try parsePrimary()
            // A "%" before an operand is the remainder, which `parseTerm` handles.
            if next == .percent, !startsOperand(at: position + 1) {
                position += 1
                operand.isPercent = true
            }
            return operand
        }

        mutating func parsePrimary() throws -> Operand {
            switch next {
            case .number(let value):
                position += 1
                return Operand(value: value)
            case .open:
                position += 1
                let inner = try parseExpression()
                guard next == .close else { throw MathError.syntax }
                position += 1
                return Operand(value: inner.plain)
            default:
                throw MathError.syntax
            }
        }

        func startsOperand(at index: Int) -> Bool {
            guard index < tokens.count else { return false }
            if case .number = tokens[index] { return true }
            return tokens[index] == .open
        }
    }

    private static func check(_ value: Decimal) throws -> Decimal {
        guard !value.isNaN else { throw MathError.outOfRange }
        return value
    }

    /// Like `%` in most languages: the sign follows the dividend.
    private static func remainder(_ dividend: Decimal, _ divisor: Decimal) -> Decimal {
        var quotient = dividend / divisor
        var whole = Decimal()
        NSDecimalRound(&whole, &quotient, 0, quotient < 0 ? .up : .down)
        return dividend - whole * divisor
    }

    private static func power(_ base: Decimal, _ exponent: Decimal) throws -> Decimal {
        if exponent == 0 { return 1 }
        if base == 0 {
            guard exponent > 0 else { throw MathError.divisionByZero }
            return 0
        }
        if base == 1 { return 1 }
        if let whole = wholeNumber(exponent), abs(whole) <= exactExponent {
            let result = pow(base, abs(whole))
            return try check(whole < 0 ? 1 / result : result)
        }
        let result = pow(NSDecimalNumber(decimal: base).doubleValue, NSDecimalNumber(decimal: exponent).doubleValue)
        guard result.isFinite, abs(result) < 1e100 else { throw MathError.outOfRange }
        return Decimal(result)
    }

    private static func wholeNumber(_ value: Decimal) -> Int? {
        var rounded = Decimal()
        var original = value
        NSDecimalRound(&rounded, &original, 0, .plain)
        guard rounded == value, abs(value) < 1e9 else { return nil }
        return NSDecimalNumber(decimal: value).intValue
    }
}
