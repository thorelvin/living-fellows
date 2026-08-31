// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.lang.classfile.ClassFile;
import java.lang.classfile.ClassModel;
import java.lang.classfile.CodeElement;
import java.lang.classfile.Instruction;
import java.lang.classfile.MethodModel;
import java.lang.classfile.instruction.InvokeInstruction;
import java.nio.file.Path;
import java.util.Enumeration;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/** Research-only caller finder for a version-pinned game method. */
public final class SCInvocationSurvey {
    private SCInvocationSurvey() {}

    public static void main(String[] args) throws Exception {
        if (args.length != 3) throw new IllegalArgumentException("jar owner method required");
        try (ZipFile zip = new ZipFile(Path.of(args[0]).toFile())) {
            Enumeration<? extends ZipEntry> entries = zip.entries();
            while (entries.hasMoreElements()) {
                ZipEntry entry = entries.nextElement();
                if (!entry.getName().endsWith(".class")) continue;
                ClassModel model;
                try {
                    model = ClassFile.of().parse(zip.getInputStream(entry).readAllBytes());
                } catch (RuntimeException failure) {
                    continue;
                }
                for (MethodModel caller : model.methods()) {
                    if (caller.code().isEmpty()) continue;
                    for (CodeElement element : caller.code().get()) {
                        if (!(element instanceof Instruction instruction)
                                || !(instruction instanceof InvokeInstruction invoke)) continue;
                        if (invoke.owner().asInternalName().equals(args[1])
                                && invoke.name().equalsString(args[2])) {
                            System.out.println(model.thisClass().asInternalName() + "."
                                    + caller.methodName().stringValue()
                                    + caller.methodType().stringValue() + " -> "
                                    + invoke.owner().asInternalName() + "."
                                    + invoke.name().stringValue() + invoke.type().stringValue());
                        }
                    }
                }
            }
        }
    }
}
