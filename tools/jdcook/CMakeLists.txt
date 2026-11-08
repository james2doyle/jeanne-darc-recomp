add_executable(jdcook main.cpp)
target_link_libraries(jdcook PRIVATE psprecore::formats)
psprecore_target_defaults(jdcook)
