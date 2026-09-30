// Preserve existing trait methods explicitly on MoonBit 0.10.14 and later.

///|
pub extend ArrowError with @debug.Debug::{to_repr}

///|
pub extend Column with @debug.Debug::{to_repr}

///|
pub extend ColumnRange with @debug.Debug::{to_repr}

///|
pub extend ColumnSummary with @debug.Debug::{to_repr}

///|
pub extend DataType with @debug.Debug::{to_repr}

///|
pub extend DataType with Eq::{equal, not_equal}

///|
pub extend Field with @debug.Debug::{to_repr}

///|
pub extend Field with Eq::{equal, not_equal}

///|
pub extend FileIndex with @debug.Debug::{to_repr}

///|
pub extend IpcData with @debug.Debug::{to_repr}

///|
pub extend KeyValue with @debug.Debug::{to_repr}

///|
pub extend KeyValue with Eq::{equal, not_equal}

///|
pub extend MessageInfo with @debug.Debug::{to_repr}

///|
pub extend MessageKind with @debug.Debug::{to_repr}

///|
pub extend MessageKind with Eq::{equal, not_equal}

///|
pub extend Predicate with @debug.Debug::{to_repr}

///|
pub extend ReadLimits with @debug.Debug::{to_repr}

///|
pub extend RecordBatch with @debug.Debug::{to_repr}

///|
pub extend Schema with @debug.Debug::{to_repr}

///|
pub extend Schema with Eq::{equal, not_equal}

///|
pub extend StreamIndex with @debug.Debug::{to_repr}

///|
pub extend TimeUnit with @debug.Debug::{to_repr}

///|
pub extend TimeUnit with Eq::{equal, not_equal}

///|
pub extend Value with @debug.Debug::{to_repr}
