//! Report datasets: specification, calculation engine and service.

pub mod engine;
pub mod service;
pub mod spec;

pub use service::{AccessClass, DatasetDescriptor, DatasetPage, DatasetService, FieldInfo, FilterInfo, FilterOption};
pub use spec::{DatasetSpec, FilterParam, I18nText};
