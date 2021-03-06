/*
 * Copyright (c) 2012 - 2018 Arvato Systems GmbH
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.arvatosystems.t9t.out.be.impl.formatgenerator;

import java.io.IOException;
import java.io.OutputStreamWriter;

import com.arvatosystems.t9t.io.CsvConfigurationDTO;
import com.arvatosystems.t9t.io.services.CSVTools;

import de.jpaw.bonaparte.core.BonaPortable;
import de.jpaw.bonaparte.core.CSVComposer3;
import de.jpaw.bonaparte.core.MessageComposer;
import de.jpaw.dp.Dependent;
import de.jpaw.dp.Named;
import de.jpaw.util.ApplicationException;

@Dependent
@Named("CSV")
public class FormatGeneratorCsv extends FoldableFormatGenerator<IOException> {

    protected OutputStreamWriter osw = null;
    protected CSVComposer3 csvComposer = null;

    @Override
    protected MessageComposer<IOException> getMessageComposer() {
        return csvComposer;
    }

    @Override
    protected void openHook() throws IOException, ApplicationException {
        CsvConfigurationDTO csvCfg = (CsvConfigurationDTO)sinkCfg.getCsvConfigurationRef();
        osw = new OutputStreamWriter(outputResource.getOutputStream(), encoding);
        csvComposer = new CSVComposer3(osw, CSVTools.getCsvConfiguration(csvCfg));
        csvComposer.startTransmission();
        super.openHook();
    }

    @Override
    public void generateData(int recordNo, int mappedRecordNo, long recordId, BonaPortable record) throws IOException, ApplicationException {
        foldingComposer.writeRecord(record);
    }

    @Override
    public void close() throws IOException, ApplicationException {
        csvComposer.terminateTransmission();
        osw.flush();
    }
}
