// Difftest runner: interprets the JSON program language (format v0) into real
// Cats Effect IO and runs it under a scripted scheduler or under TestControl.
// Spec: wiki/methodology/difftest-program-format.md
//
// The CE version is pinned to 3.7.1. Override it for a second build, for example
// with a `series/3.x` snapshot that `sbt publishLocal` in ~/Projects/cats-effect made:
//   sbt -Dce.version=3.7-abcdef0-SNAPSHOT test
val ceVersion = sys.props.getOrElse("ce.version", "3.7.1")

ThisBuild / scalaVersion := "3.10.1"
ThisBuild / organization := "cats-effect-in-lean"

lazy val difftest = (project in file("."))
  .settings(
    name := "difftest",
    resolvers ++= (if (ceVersion == "3.7.1") Nil else Seq(Resolver.sonatypeCentralSnapshots)),
    libraryDependencies ++= Seq(
      "org.typelevel" %% "cats-effect" % ceVersion,
      "org.typelevel" %% "cats-effect-testkit" % ceVersion,
      "com.lihaoyi" %% "ujson" % "4.4.3",
      "org.scalameta" %% "munit" % "1.2.4" % Test
    ),
    scalacOptions ++= Seq("-deprecation", "-feature", "-Wunused:all"),
    Compile / run / fork := true,
    Compile / run / connectInput := true,
    Compile / run / outputStrategy := Some(StdoutOutput)
  )
