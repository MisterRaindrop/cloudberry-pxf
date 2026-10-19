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

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.hadoop.hive.serde.serdeConstants;
import org.apache.cloudberry.pxf.api.utilities.ColumnDescriptor;

import java.util.ArrayList;
import java.util.List;
import java.util.Properties;

import static org.apache.hadoop.hive.metastore.api.hive_metastoreConstants.META_TABLE_COLUMN_TYPES;

/**
 * Specialized HiveResolver for a Hive table stored as RC file.
 * Use together with HiveInputFormatFragmenter/HiveRCFileAccessor.
 */
public class HiveORCSerdeResolver extends HiveResolver {
    private static final Log LOG = LogFactory.getLog(HiveORCSerdeResolver.class);

    @Override
    protected Properties getSerdeProperties() {
        int numberOfDataColumns = context.getColumns() - getNumberOfPartitions();

        LOG.debug("Serde number of columns is " + numberOfDataColumns);

        Properties properties = super.getSerdeProperties();
        StringBuilder columnNames = new StringBuilder(numberOfDataColumns * 2); // column + delimiter
        StringBuilder columnTypes = new StringBuilder(numberOfDataColumns * 2); // column + delimiter
        String[] hiveColTypes = splitColumnTypes(properties.getProperty(META_TABLE_COLUMN_TYPES));

        String delim = ",";
        for (int j = 0; j < context.getTupleDescription().size(); j++) {
            ColumnDescriptor column = context.getColumn(j);
            Integer i = hiveIndexes.get(j);
            if (i == null) continue;

            String columnName = column.columnName();
            String columnType = hiveUtilities.toCompatibleHiveType(column.getDataType(), column.columnTypeModifiers());
            //Complex Types will have a mismatch between Hive and Gpdb type
            if (!columnType.equals(hiveColTypes[i])) {
                columnType = hiveColTypes[i];
            }
            if (columnNames.length() > 0) {
                columnNames.append(delim);
                columnTypes.append(delim);
            }
            columnNames.append(columnName);
            columnTypes.append(columnType);
        }
        properties.put(serdeConstants.LIST_COLUMNS, columnNames.toString());
        properties.put(serdeConstants.LIST_COLUMN_TYPES, columnTypes.toString());
        return properties;
    }

    /**
     * Splits the colon separated list of Hive column types (META_TABLE_COLUMN_TYPES) into
     * one type per column. Inside struct types a colon also separates a field name from
     * its type (e.g. "struct<a:array<int>,b:int>"), so only colons outside of angle
     * brackets separate columns.
     *
     * @param columnTypes colon separated column types
     * @return the type of each column
     */
    static String[] splitColumnTypes(String columnTypes) {
        List<String> types = new ArrayList<>();
        int depth = 0;
        int start = 0;
        for (int i = 0; i < columnTypes.length(); i++) {
            char c = columnTypes.charAt(i);
            if (c == '<') {
                depth++;
            } else if (c == '>') {
                depth--;
            } else if (c == ':' && depth == 0) {
                types.add(columnTypes.substring(start, i));
                start = i + 1;
            }
        }
        types.add(columnTypes.substring(start));
        return types.toArray(new String[0]);
    }
}
