package utils

import (
    "github.com/sirupsen/logrus"
    "os"
    "strings"
)

var Logger = logrus.New()

type appNameHook struct {
    appName string
}

// Levels implements logrus.Hook interface.
func (h *appNameHook) Levels() []logrus.Level {
    return logrus.AllLevels
}

// Fire implements logrus.Hook interface.
func (h *appNameHook) Fire(entry *logrus.Entry) error {
    entry.Message = "[" + h.appName + "] " + entry.Message
    return nil
}

func InitLogger(appName string) {
    Logger.SetOutput(os.Stdout)

    logLevelStr := strings.ToLower(os.Getenv("LOG_LEVEL"))
	if logLevelStr == "" {
		logLevelStr = "info"
	}
	level, err := logrus.ParseLevel(logLevelStr)
	if err != nil {
		Logger.Warnf("Invalid LOG_LEVEL '%s', defaulting to INFO", logLevelStr)
		level = logrus.InfoLevel
	}
	Logger.SetLevel(level)

    Logger.SetFormatter(&logrus.TextFormatter{
        FullTimestamp: true,
    })

    Logger.AddHook(&appNameHook{appName})
}

