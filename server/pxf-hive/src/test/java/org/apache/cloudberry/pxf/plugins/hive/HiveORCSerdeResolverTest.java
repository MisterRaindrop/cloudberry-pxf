package org.apache.cloudberry.pxf.plugins.hive;

/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;

public class HiveORCSerdeResolverTest {

    @Test
    public void testSplitColumnTypesPrimitives() {
        assertArrayEquals(new String[]{"int", "string", "decimal(10,2)"},
                HiveORCSerdeResolver.splitColumnTypes("int:string:decimal(10,2)"));
    }

    @Test
    public void testSplitColumnTypesStructWithComplexField() {
        assertArrayEquals(new String[]{"int", "struct<a:array<int>,b:int>", "string"},
                HiveORCSerdeResolver.splitColumnTypes("int:struct<a:array<int>,b:int>:string"));
        assertArrayEquals(new String[]{"struct<m:map<string,int>,b:string>", "string"},
                HiveORCSerdeResolver.splitColumnTypes("struct<m:map<string,int>,b:string>:string"));
    }

    @Test
    public void testSplitColumnTypesNestedStruct() {
        assertArrayEquals(new String[]{"int", "struct<p:struct<q:array<int>,r:map<string,string>>,t:string>", "array<array<int>>"},
                HiveORCSerdeResolver.splitColumnTypes("int:struct<p:struct<q:array<int>,r:map<string,string>>,t:string>:array<array<int>>"));
    }

    @Test
    public void testSplitColumnTypesStructInsideCollections() {
        assertArrayEquals(new String[]{"array<struct<x:int,y:string>>", "map<string,struct<a:int>>"},
                HiveORCSerdeResolver.splitColumnTypes("array<struct<x:int,y:string>>:map<string,struct<a:int>>"));
    }
}
