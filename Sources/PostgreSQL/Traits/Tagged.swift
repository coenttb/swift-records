#if Tagged
public import Tagged

extension Tagged: PostgreSQL.DataType
where Tag: ~Copyable & ~Escapable, Underlying: PostgreSQL.DataType {
    public static var typeName: String { Underlying.typeName }
}
#endif
